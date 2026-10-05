/// Player side controller wrapping the pure Dart [QuizClient].
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/models/models.dart';
import '../../core/net/quiz_client.dart';
import '../../core/protocol/messages.dart';

/// UI state of the player screens.
final class PlayerSessionState extends Equatable {
  /// Creates a player session state.
  const PlayerSessionState({
    this.status = QuizClientStatus.disconnected,
    this.game,
    this.playerId,
    this.serverName,
    this.error,
    this.clockOffsetMicros = 0,
    this.roundTripMicros = 0,
    this.lastSubmittedOptionId,
    this.hasBuzzed = false,
    this.lobby,
  });

  /// Connection lifecycle.
  final QuizClientStatus status;

  /// Latest redacted snapshot pushed by the host.
  final GameState? game;

  /// Server assigned identifier of this player.
  final String? playerId;

  /// Friendly name of the host.
  final String? serverName;

  /// Message of the last failure.
  final String? error;

  /// Measured `client - host` clock offset.
  final int clockOffsetMicros;

  /// Round trip time backing the offset.
  final int roundTripMicros;

  /// Option this client already sent for the running round.
  final String? lastSubmittedOptionId;

  /// Whether this client already buzzed in the running round.
  final bool hasBuzzed;
  final LobbySnapshotMessage? lobby;
  bool get isChoosingTeam =>
      lobby != null &&
      playerId == null &&
      (status == QuizClientStatus.connected ||
          status == QuizClientStatus.connecting);

  /// Whether the socket is open and the join was accepted.
  bool get isConnected =>
      status == QuizClientStatus.connected && playerId != null;

  /// The question currently on stage.
  Question? get question => game?.round.question;

  /// The round lifecycle position reported by the host.
  RoundStatus get roundStatus => game?.round.status ?? RoundStatus.idle;

  /// This player's entry in the broadcast snapshot.
  Player? get me {
    final id = playerId;
    return id == null ? null : game?.players[id];
  }

  /// Current score of this player.
  int get myScore => game?.poker == null
      ? (playerId == null ? 0 : game?.scores.scoreOf(playerId!) ?? 0)
      : game!.poker!.chips[me?.teamId] ?? 0;

  bool get mayAnswerPoker {
    final poker = game?.poker;
    if (poker == null) return true;
    return !poker.betting &&
        (poker.wagers[me?.teamId] ?? 0) > 0 &&
        !poker.settledTeamIds.contains(me?.teamId) &&
        !game!.round.answers.keys.any(
          (id) => game!.players[id]?.teamId == me?.teamId,
        );
  }

  /// Estimated one way latency to the host.
  Duration get latency => Duration(microseconds: roundTripMicros ~/ 2);

  /// Returns a copy with the given fields replaced.
  PlayerSessionState copyWith({
    QuizClientStatus? status,
    GameState? game,
    String? playerId,
    String? serverName,
    String? error,
    int? clockOffsetMicros,
    int? roundTripMicros,
    String? lastSubmittedOptionId,
    bool? hasBuzzed,
    bool clearError = false,
    bool clearSubmission = false,
    LobbySnapshotMessage? lobby,
  }) => PlayerSessionState(
    status: status ?? this.status,
    game: game ?? this.game,
    playerId: playerId ?? this.playerId,
    serverName: serverName ?? this.serverName,
    error: clearError ? null : error ?? this.error,
    clockOffsetMicros: clockOffsetMicros ?? this.clockOffsetMicros,
    roundTripMicros: roundTripMicros ?? this.roundTripMicros,
    lastSubmittedOptionId: clearSubmission
        ? null
        : lastSubmittedOptionId ?? this.lastSubmittedOptionId,
    hasBuzzed: clearSubmission ? false : hasBuzzed ?? this.hasBuzzed,
    lobby: lobby ?? this.lobby,
  );

  @override
  List<Object?> get props => [
    status,
    game,
    playerId,
    serverName,
    error,
    clockOffsetMicros,
    roundTripMicros,
    lastSubmittedOptionId,
    hasBuzzed,
    lobby,
  ];
}

/// Drives one player client: handshake, join, buzz and answer.
class PlayerSessionCubit extends Cubit<PlayerSessionState> {
  /// Creates a disconnected session controller.
  PlayerSessionCubit() : super(const PlayerSessionState());

  QuizClient? _client;
  Uri? mediaBaseUri;
  StreamSubscription<GameState>? _gameSubscription;
  StreamSubscription<QuizClientStatus>? _statusSubscription;
  StreamSubscription<ProtocolErrorMessage>? _errorSubscription;
  StreamSubscription<LobbySnapshotMessage>? _lobbySubscription;
  String _joiningName = '';
  String? _lastQuestionId;
  int? _lastRoundStart;

  /// Connects to the host at [baseUri] and joins as [name].
  Future<void> connect({
    required Uri baseUri,
    required String name,
    String? teamId,
    bool lobbyOnly = false,
  }) async {
    await _teardown();
    emit(PlayerSessionState(status: QuizClientStatus.connecting));

    mediaBaseUri = baseUri;
    final client = QuizClient(baseUri: baseUri);
    _client = client;
    _joiningName = name;
    _lobbySubscription = client.lobbies.listen((lobby) {
      if (!isClosed) emit(state.copyWith(lobby: lobby));
    });

    _gameSubscription = client.games.listen(_onSnapshot);
    _statusSubscription = client.statuses.listen((status) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: status,
          playerId: client.playerId,
          serverName: client.serverName,
          clockOffsetMicros: client.clock.clockOffsetMicros,
          roundTripMicros: client.clock.roundTripMicros,
        ),
      );
    });
    _errorSubscription = client.errors.listen((error) {
      if (isClosed) return;
      emit(state.copyWith(error: error.message));
    });

    try {
      if (lobbyOnly) {
        await client.browseLobby();
      } else {
        await client.connect(name: name, teamId: teamId);
      }
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(status: QuizClientStatus.failed, error: '$error'));
    }
  }

  Future<void> joinTeam({String? teamId, String? newTeamName}) async {
    final client = _client;
    if (client == null ||
        !state.isChoosingTeam ||
        state.status == QuizClientStatus.connecting) {
      return;
    }
    emit(state.copyWith(clearError: true));
    try {
      await client.connect(
        name: _joiningName,
        teamId: teamId,
        newTeamName: newTeamName,
      );
    } on Object catch (error) {
      if (!isClosed) emit(state.copyWith(error: '$error'));
    }
  }

  void renameTeam(String name) {
    emit(state.copyWith(clearError: true));
    _client?.renameTeam(name);
  }

  /// Sends a buzzer press for the question on stage.
  ///
  /// Called from `Listener.onPointerDown`, so the timestamp is taken as close
  /// to the physical touch as the framework allows.
  void buzz() {
    final question = state.question;
    if (question is! BuzzerQuestion ||
        state.hasBuzzed ||
        !state.mayAnswerPoker) {
      return;
    }
    _client?.pressBuzzer(question.id);
    emit(state.copyWith(hasBuzzed: true));
  }

  /// Sends the choice [optionId] for the question on stage.
  void choose(String optionId) {
    final question = state.question;
    if (!state.mayAnswerPoker ||
        question is! MultipleChoiceQuestion ||
        state.lastSubmittedOptionId != null) {
      return;
    }
    _client?.submitChoice(questionId: question.id, optionId: optionId);
    emit(state.copyWith(lastSubmittedOptionId: optionId));
  }

  void submit(
    AnswerSubmission Function(String playerId, int timestamp, int offset) build,
  ) {
    if (!state.mayAnswerPoker ||
        !state.isConnected ||
        state.lastSubmittedOptionId != null ||
        !state.roundStatus.acceptsInput) {
      return;
    }
    _client?.submitAnswer(build);
    emit(state.copyWith(lastSubmittedOptionId: 'submitted'));
  }

  void selectJeopardyCell(String questionId) =>
      _client?.selectJeopardyCell(questionId);
  void placeDailyDoubleWager(String questionId, int wager) =>
      _client?.placeDailyDoubleWager(questionId, wager);

  void placePokerWager(int wager) {
    final question = state.question;
    if (question == null || !(state.game?.poker?.betting ?? false)) return;
    _client?.placePokerWager(questionId: question.id, wager: wager);
  }

  /// Leaves the session.
  Future<void> disconnect() async {
    await _teardown();
    if (isClosed) return;
    emit(const PlayerSessionState());
  }

  @override
  Future<void> close() async {
    await _teardown();
    return super.close();
  }

  void _onSnapshot(GameState game) {
    if (isClosed) return;
    final questionId = game.round.question?.id;
    final isNewRound =
        questionId != _lastQuestionId ||
        game.round.startedAtHostMicros != _lastRoundStart;
    _lastRoundStart = game.round.startedAtHostMicros;
    _lastQuestionId = questionId;

    final client = _client;
    final id = client?.playerId ?? state.playerId;

    // The buzzer reopens after a wrong steal, so the local "already buzzed"
    // guard has to follow the authoritative queue instead of latching forever.
    final stillQueued =
        id != null &&
        game.round.buzzerQueue.any((press) => press.playerId == id);
    final hasBuzzed = isNewRound
        ? false
        : stillQueued || !game.round.status.acceptsInput && state.hasBuzzed;

    emit(
      state.copyWith(
        game: game,
        playerId: id,
        clockOffsetMicros: client?.clock.clockOffsetMicros,
        roundTripMicros: client?.clock.roundTripMicros,
        clearSubmission: isNewRound,
        hasBuzzed: hasBuzzed,
      ),
    );
  }

  Future<void> _teardown() async {
    await _gameSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _lobbySubscription?.cancel();
    _gameSubscription = null;
    _statusSubscription = null;
    _errorSubscription = null;
    _lobbySubscription = null;
    _lastQuestionId = null;
    await _client?.dispose();
    _client = null;
  }
}
