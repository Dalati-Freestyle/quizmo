/// Player side controller wrapping the pure Dart [QuizClient].
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/models/models.dart';
import '../../core/engine/quiz_engine_event.dart';
import '../../core/sync/clock.dart';
import '../../core/net/quiz_client.dart';
import '../../core/net/session_uri.dart';
import '../../core/protocol/messages.dart';
import 'player_session_store.dart';

enum SubmissionStatus { idle, sending, accepted, uncertain, rejected }

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
    this.waitingForApproval = false,
    this.submissionStatus = SubmissionStatus.idle,
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
  final bool waitingForApproval;
  final SubmissionStatus submissionStatus;
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

  bool get mayAnswerQuestion => game?.mayAnswerQuestion(playerId) ?? false;

  bool get mayAnswerPoker {
    final poker = game?.poker;
    if (poker == null) return true;
    return !poker.betting &&
        me?.teamId != null &&
        ((poker.wagers[me?.teamId] ?? 0) > 0 ||
            (poker.chips[me?.teamId] ?? 0) == 0) &&
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
    bool? waitingForApproval,
    SubmissionStatus? submissionStatus,
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
    waitingForApproval: waitingForApproval ?? this.waitingForApproval,
    submissionStatus:
        submissionStatus ??
        (clearSubmission ? SubmissionStatus.idle : this.submissionStatus),
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
    waitingForApproval,
    submissionStatus,
  ];
}

/// Drives one player client: handshake, join, buzz and answer.
class PlayerSessionCubit extends Cubit<PlayerSessionState> {
  /// Creates a disconnected session controller.
  PlayerSessionCubit({
    PlayerSessionStore? store,
    QuizClient Function(Uri)? createClient,
  }) : _store = store ?? PlayerSessionStore(),
       _createClient = createClient ?? ((host) => QuizClient(baseUri: host)),
       _localSend = null,
       _localNow = null,
       super(const PlayerSessionState());

  PlayerSessionCubit.local({
    required String playerId,
    required GameState initialGame,
    required Stream<GameState> snapshots,
    required void Function(QuizEngineEvent) send,
    required NowMicros now,
  }) : _store = PlayerSessionStore(),
       _createClient = ((host) => QuizClient(baseUri: host)),
       _localSend = send,
       _localNow = now,
       super(
         PlayerSessionState(
           status: QuizClientStatus.connected,
           playerId: playerId,
           game: initialGame,
         ),
       ) {
    _onSnapshot(initialGame);
    _gameSubscription = snapshots.listen(_onSnapshot);
  }

  final void Function(QuizEngineEvent)? _localSend;
  final NowMicros? _localNow;
  final PlayerSessionStore _store;
  final QuizClient Function(Uri) _createClient;
  SavedPlayerSession? _saved;
  Timer? _retryTimer;
  bool _intentionalDisconnect = false;
  bool _connecting = false;
  Timer? _submissionTimer;
  bool _restoringSnapshot = true;

  Future<void> restore({Uri? host}) async {
    try {
      final saved = await _store.read();
      if (isClosed ||
          saved == null ||
          (host != null && !samePlayerSession(saved.host, host))) {
        return;
      }
      _saved = saved;
      await connect(baseUri: host ?? saved.host, name: saved.name);
    } on Object catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(error: 'Sitzung konnte nicht geladen werden: $error'),
        );
      }
    }
  }

  Future<void> _remember() async {
    final client = _client;
    if (client?.playerId == null ||
        client?.resumeToken == null ||
        mediaBaseUri == null) {
      return;
    }
    _saved = SavedPlayerSession(
      host: _baseUri!,
      name: _joiningName,
      playerId: client!.playerId!,
      token: client.resumeToken!,
    );
    try {
      await _store.save(_saved!);
    } on Object catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            error:
                'Automatischer Reconnect nach Neustart konnte nicht gespeichert werden: $error',
          ),
        );
      }
    }
  }

  void _scheduleReconnect() {
    if (isClosed ||
        _intentionalDisconnect ||
        _saved == null ||
        _connecting ||
        _retryTimer != null) {
      return;
    }
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _retryTimer = null;
      unawaited(_reconnect());
    });
    emit(state.copyWith(status: QuizClientStatus.reconnecting));
  }

  Future<void> _reconnect() async {
    final client = _client;
    final saved = _saved;
    if (client == null ||
        saved == null ||
        _connecting ||
        isClosed ||
        _intentionalDisconnect) {
      return;
    }
    _connecting = true;
    try {
      await client.connect(
        name: saved.name,
        resumePlayerId: saved.playerId,
        resumeToken: saved.token,
      );
      if (!isClosed) emit(state.copyWith(clearError: true));
    } on Object catch (error) {
      if (error is JoinRejectedException && error.code == 'hostClosed') {
        _stopForClosedRoom(error.message);
        return;
      }
      if (!isClosed && !_intentionalDisconnect) {
        emit(
          state.copyWith(
            error: mediaBaseUri != null && isInternetSession(mediaBaseUri!)
                ? 'Connection interrupted. Reconnecting to the room...'
                : 'Verbindung unterbrochen. Erneuter Versuch ...',
          ),
        );
      }
    } finally {
      _connecting = false;
      if (!isClosed && !state.isConnected) _scheduleReconnect();
    }
  }

  void resume() {
    if (state.isConnected) {
      unawaited(_client?.checkConnection());
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
      unawaited(_reconnect());
    }
  }

  QuizClient? _client;
  Uri? _baseUri;
  Uri? get mediaBaseUri => _client?.mediaBaseUri ?? _baseUri;
  StreamSubscription<GameState>? _gameSubscription;
  StreamSubscription<GameSnapshotMessage>? _snapshotSubscription;
  StreamSubscription<QuizClientStatus>? _statusSubscription;
  StreamSubscription<ProtocolErrorMessage>? _errorSubscription;
  StreamSubscription<LobbySnapshotMessage>? _lobbySubscription;
  StreamSubscription<bool>? _admissionSubscription;
  String _joiningName = '';
  String? _lastQuestionId;
  int? _lastRoundStart;

  /// Connects to the host at [baseUri] and joins as [name].
  Future<void> connect({
    required Uri baseUri,
    required String name,
    String? teamId,
    String? joinCode,
    bool lobbyOnly = false,
  }) async {
    await _teardown();
    _intentionalDisconnect = false;
    _connecting = true;
    if (_saved == null) {
      try {
        _saved = await _store.read();
      } on Object {
        /* Storage failures are reported when saving. */
      }
    }
    if (isClosed) return;
    if (_saved == null ||
        !samePlayerSession(_saved!.host, baseUri) ||
        _saved?.name != name) {
      _saved = null;
    }
    emit(PlayerSessionState(status: QuizClientStatus.connecting));

    _baseUri = baseUri;
    final client = _createClient(baseUri);
    _client = client;
    _joiningName = name;
    _lobbySubscription = client.lobbies.listen((lobby) {
      if (!isClosed) emit(state.copyWith(lobby: lobby));
    });
    _admissionSubscription = client.admissions.listen((waiting) {
      if (!isClosed) emit(state.copyWith(waitingForApproval: waiting));
    });

    _snapshotSubscription = client.snapshots.listen((snapshot) {
      _onSnapshot(snapshot.game, accepted: snapshot.ownSubmissionAccepted);
    });
    _statusSubscription = client.statuses.listen((status) {
      if (isClosed) return;
      if (status == QuizClientStatus.closed) {
        _stopForClosedRoom(
          'The host has closed this room. Join a new room to continue.',
        );
        return;
      }
      if (status != QuizClientStatus.connected) _restoringSnapshot = true;
      emit(
        state.copyWith(
          status:
              _intentionalDisconnect && state.status == QuizClientStatus.closed
              ? QuizClientStatus.closed
              : !_intentionalDisconnect &&
                    _saved != null &&
                    status != QuizClientStatus.connected
              ? QuizClientStatus.reconnecting
              : status,
          playerId: client.playerId,
          serverName: client.serverName,
          clockOffsetMicros: client.clock.clockOffsetMicros,
          roundTripMicros: client.clock.roundTripMicros,
          submissionStatus:
              status != QuizClientStatus.connected &&
                  state.submissionStatus == SubmissionStatus.sending
              ? SubmissionStatus.uncertain
              : null,
        ),
      );
      if (status == QuizClientStatus.connected && client.playerId != null) {
        unawaited(_remember());
      }
      if (status == QuizClientStatus.disconnected ||
          status == QuizClientStatus.failed) {
        _scheduleReconnect();
      }
    });
    _errorSubscription = client.errors.listen((error) {
      if (isClosed) return;
      emit(state.copyWith(error: error.message));
      if (error.code == 'invalidTimestamp' || error.code == 'notJoined') {
        _submissionTimer?.cancel();
        emit(state.copyWith(submissionStatus: SubmissionStatus.rejected));
      }
      if (error.code == 'hostClosed') {
        _stopForClosedRoom(error.message);
      }
      if (error.code == 'sessionReplaced') {
        _intentionalDisconnect = true;
        _retryTimer?.cancel();
        _retryTimer = null;
        emit(state.copyWith(status: QuizClientStatus.closed));
      }
      if (error.code == 'kicked' ||
          error.code == 'invalidResume' ||
          error.code == 'banned') {
        _saved = null;
        _intentionalDisconnect = true;
        _retryTimer?.cancel();
        _retryTimer = null;
        unawaited(_forgetRejectedSession(client, error.message));
      }
    });

    try {
      if (_saved case final saved?) {
        await client.connect(
          name: name,
          resumePlayerId: saved.playerId,
          resumeToken: saved.token,
        );
      } else if (lobbyOnly) {
        await client.browseLobby();
      } else {
        await client.connect(name: name, teamId: teamId, joinCode: joinCode);
      }
      if (!isClosed && client.playerId != null) {
        emit(
          state.copyWith(
            status: client.status,
            playerId: client.playerId,
            serverName: client.serverName,
            clearError: true,
          ),
        );
        await _remember();
      }
    } on Object catch (error) {
      if (error is JoinRejectedException && error.code == 'hostClosed') {
        _stopForClosedRoom(error.message);
        return;
      }
      if (isClosed || _intentionalDisconnect) return;
      emit(
        state.copyWith(
          status: QuizClientStatus.failed,
          error: error is JoinRejectedException
              ? error.message
              : isInternetSession(baseUri)
              ? 'Connection interrupted. Reconnecting to the room...'
              : '$error',
        ),
      );
    } finally {
      _connecting = false;
      if (!state.isConnected) _scheduleReconnect();
    }
  }

  void _stopForClosedRoom(String message) {
    if (isClosed) return;
    _intentionalDisconnect = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _submissionTimer?.cancel();
    emit(
      state.copyWith(
        status: QuizClientStatus.closed,
        error: message,
        submissionStatus: state.submissionStatus == SubmissionStatus.sending
            ? SubmissionStatus.uncertain
            : null,
      ),
    );
  }

  void _beginSubmission({String? optionId, bool buzzer = false}) {
    emit(
      state.copyWith(
        lastSubmittedOptionId: buzzer ? null : optionId ?? 'submitted',
        hasBuzzed: buzzer ? true : null,
        submissionStatus: SubmissionStatus.sending,
        clearError: true,
      ),
    );
    _submissionTimer?.cancel();
    _submissionTimer = Timer(const Duration(seconds: 5), () {
      if (isClosed || state.submissionStatus != SubmissionStatus.sending) {
        return;
      }
      emit(state.copyWith(submissionStatus: SubmissionStatus.uncertain));
      // Rejoin fetches the committed snapshot even when only the confirmation
      // was lost. Never replay a timestamped answer into a later round.
      unawaited(_client?.disconnect());
    });
  }

  Future<void> _forgetRejectedSession(QuizClient client, String message) async {
    try {
      await _store.clear();
    } on Object {
      /* Keep the rejection visible. */
    }
    if (isClosed || _client != client) return;
    await client.disconnect();
    if (!isClosed) {
      emit(PlayerSessionState(status: QuizClientStatus.closed, error: message));
    }
  }

  Future<void> joinTeam({
    String? teamId,
    String? newTeamName,
    String? joinCode,
  }) async {
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
        joinCode: joinCode,
      );
    } on Object catch (error) {
      if (!isClosed && !_intentionalDisconnect && _client == client) {
        emit(state.copyWith(error: '$error'));
      }
    }
  }

  void renameTeam(String name) {
    if (!state.isConnected) return;
    emit(state.copyWith(clearError: true));
    if (_localSend case final send?) {
      send(RenameTeamEvent(playerId: state.playerId!, name: name));
    } else {
      _client?.renameTeam(name);
    }
  }

  /// Sends a buzzer press for the question on stage.
  ///
  /// Called from `Listener.onPointerDown`, so the timestamp is taken as close
  /// to the physical touch as the framework allows.
  void buzz() {
    final question = state.question;
    if (!state.isConnected ||
        !state.roundStatus.acceptsInput ||
        state.game!.round.lockedOutPlayerIds.contains(state.playerId) ||
        question is! BuzzerQuestion ||
        state.hasBuzzed ||
        !state.mayAnswerQuestion ||
        !state.mayAnswerPoker) {
      return;
    }
    _beginSubmission(buzzer: true);
    if (_localSend case final send?) {
      send(
        BuzzerPressEvent(
          BuzzerPress(
            playerId: state.playerId!,
            questionId: question.id,
            clientTimestampMicros: _localNow!(),
            clockOffsetMicros: 0,
          ),
        ),
      );
    } else {
      _deliverSubmission(() => _client!.pressBuzzer(question.id));
    }
  }

  /// Sends the choice [optionId] for the question on stage.
  void choose(String optionId) {
    final question = state.question;
    if (!state.isConnected ||
        !state.roundStatus.acceptsInput ||
        !state.mayAnswerQuestion ||
        !state.mayAnswerPoker ||
        question is! MultipleChoiceQuestion ||
        state.lastSubmittedOptionId != null) {
      return;
    }
    _beginSubmission(optionId: optionId);
    if (_localSend case final send?) {
      send(
        SubmitAnswerEvent(
          MultipleChoiceAnswer(
            playerId: state.playerId!,
            questionId: question.id,
            clientTimestampMicros: _localNow!(),
            clockOffsetMicros: 0,
            optionId: optionId,
          ),
        ),
      );
    } else {
      _deliverSubmission(
        () =>
            _client!.submitChoice(questionId: question.id, optionId: optionId),
      );
    }
  }

  void submit(
    AnswerSubmission Function(String playerId, int timestamp, int offset) build,
  ) {
    if (!state.mayAnswerQuestion ||
        !state.mayAnswerPoker ||
        !state.isConnected ||
        state.lastSubmittedOptionId != null ||
        !state.roundStatus.acceptsInput) {
      return;
    }
    _beginSubmission();
    if (_localSend case final send?) {
      send(SubmitAnswerEvent(build(state.playerId!, _localNow!(), 0)));
    } else {
      _deliverSubmission(() => _client!.submitAnswer(build));
    }
  }

  void _deliverSubmission(void Function() send) {
    try {
      send();
    } on StateError {
      emit(
        state.copyWith(
          submissionStatus: SubmissionStatus.uncertain,
          error: 'Confirmation missing. Your answer may not have arrived.',
        ),
      );
      unawaited(_client?.disconnect());
    }
  }

  void chooseMultiple(List<String> optionIds) {
    final question = state.question;
    if (question is! MultipleChoiceQuestion ||
        !question.allowMultipleAnswers ||
        optionIds.isEmpty) {
      return;
    }
    submit(
      (id, timestamp, offset) => MultipleChoiceAnswer(
        playerId: id,
        questionId: question.id,
        clientTimestampMicros: timestamp,
        clockOffsetMicros: offset,
        optionIds: List.unmodifiable(optionIds),
      ),
    );
  }

  void selectJeopardyCell(String questionId) {
    if (!state.isConnected ||
        !(state.game?.mayPickQuestion(state.playerId) ?? false) ||
        state.game?.jeopardy?.pendingPickQuestionId != null) {
      return;
    }
    if (_localSend case final send?) {
      send(SelectJeopardyCellEvent(questionId, playerId: state.playerId));
    } else {
      _client?.selectJeopardyCell(questionId);
    }
  }

  void placeDailyDoubleWager(String questionId, int wager) {
    if (!state.isConnected || state.game?.recoveryPaused == true) return;
    if (_localSend case final send?) {
      send(
        PlaceDailyDoubleWagerEvent(
          wager,
          playerId: state.playerId,
          questionId: questionId,
        ),
      );
    } else {
      _client?.placeDailyDoubleWager(questionId, wager);
    }
  }

  void placePokerWager(int wager) {
    final question = state.question;
    if (!state.isConnected ||
        state.game?.recoveryPaused == true ||
        question == null ||
        !(state.game?.poker?.betting ?? false)) {
      return;
    }
    if (_localSend case final send?) {
      send(
        PlacePokerWagerEvent(
          playerId: state.playerId!,
          questionId: question.id,
          wager: wager,
        ),
      );
    } else {
      _client?.placePokerWager(questionId: question.id, wager: wager);
    }
  }

  /// Leaves the session.
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _saved = null;
    if (_localSend == null) await _store.clear();
    await _teardown();
    if (isClosed) return;
    emit(const PlayerSessionState());
  }

  @override
  Future<void> close() async {
    _intentionalDisconnect = true;
    await _teardown();
    return super.close();
  }

  void _onSnapshot(GameState game, {bool? accepted}) {
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
    final hasBuzzed = stillQueued;
    final answer = game.round.answers[id];
    final confirmed = accepted ?? (id != null && game.round.hasSubmitted(id));
    final receiptKnown =
        accepted != null ||
        _localSend != null ||
        game.poker == null ||
        game.round.status == RoundStatus.revealed;
    final restored = _restoringSnapshot;
    _restoringSnapshot = false;
    final pending =
        !isNewRound &&
        (state.submissionStatus == SubmissionStatus.sending ||
            state.submissionStatus == SubmissionStatus.uncertain);
    final keepPending = pending && !confirmed && (!restored || !receiptKnown);
    if (!keepPending) _submissionTimer?.cancel();

    final baseline = isNewRound ? state.copyWith(clearSubmission: true) : state;
    emit(
      baseline.copyWith(
        game: game,
        playerId: id,
        clockOffsetMicros: client?.clock.clockOffsetMicros,
        roundTripMicros: client?.clock.roundTripMicros,
        clearSubmission: !confirmed && !keepPending,
        lastSubmittedOptionId: answer is MultipleChoiceAnswer
            ? (answer.optionIds == null ? answer.optionId : 'submitted')
            : confirmed
            ? 'submitted'
            : null,
        hasBuzzed: hasBuzzed || (keepPending && state.hasBuzzed),
        submissionStatus: confirmed
            ? SubmissionStatus.accepted
            : keepPending
            ? state.submissionStatus
            : pending
            ? SubmissionStatus.rejected
            : !isNewRound && state.submissionStatus == SubmissionStatus.rejected
            ? SubmissionStatus.rejected
            : SubmissionStatus.idle,
      ),
    );
  }

  Future<void> _teardown() async {
    _submissionTimer?.cancel();
    _restoringSnapshot = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _gameSubscription?.cancel();
    await _snapshotSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _lobbySubscription?.cancel();
    await _admissionSubscription?.cancel();
    _gameSubscription = null;
    _snapshotSubscription = null;
    _statusSubscription = null;
    _errorSubscription = null;
    _lobbySubscription = null;
    _admissionSubscription = null;
    _lastQuestionId = null;
    await _client?.dispose();
    _client = null;
  }
}
