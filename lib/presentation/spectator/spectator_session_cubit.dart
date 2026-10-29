/// Spectator side controller: a read-only, self-healing view of the session.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/models/models.dart';
import '../../core/net/quiz_client.dart';
import '../../core/protocol/messages.dart';

/// Creates the [QuizClient] used by a [SpectatorSessionCubit].
typedef QuizClientFactory = QuizClient Function(Uri baseUri);

QuizClient _defaultClientFactory(Uri baseUri) => QuizClient(baseUri: baseUri);

/// UI state of the TV screen.
final class SpectatorSessionState extends Equatable {
  /// Creates a spectator state.
  const SpectatorSessionState({
    this.status = QuizClientStatus.disconnected,
    this.game,
    this.serverName,
    this.error,
    this.snapshotReceivedAt,
    this.reconnectAttempt = 0,
    this.extrapolateTime = true,
    this.mediaBaseUri,
  });

  /// Connection lifecycle.
  final QuizClientStatus status;

  /// Latest redacted snapshot; kept across reconnects so the TV never goes
  /// blank because of a short Wi-Fi hiccup.
  final GameState? game;

  /// Friendly name of the host.
  final String? serverName;

  /// Message of the last failure.
  final String? error;

  /// Local instant at which [game] arrived, the anchor of the countdown.
  final DateTime? snapshotReceivedAt;

  /// How many reconnects were attempted since the last healthy connection.
  final int reconnectAttempt;
  final bool extrapolateTime;
  final Uri? mediaBaseUri;

  /// Whether the socket is open and the host accepted the watch request.
  bool get isConnected => status == QuizClientStatus.connected;

  /// Time left for the running round, or `null` when no clock is ticking.
  ///
  /// The TV has no clock handshake, so the elapsed time is derived from the
  /// *host* timestamps inside the snapshot plus the local time that passed
  /// since the snapshot arrived. Both are durations, so the offset between the
  /// two wall clocks cancels out.
  Duration? remainingTime(DateTime now) {
    final game = this.game;
    final receivedAt = snapshotReceivedAt;
    final round = game?.round;
    final question = round?.question;
    final startedAt = round?.timerStartedAtHostMicros;
    if (game == null ||
        receivedAt == null ||
        round == null ||
        question == null ||
        startedAt == null ||
        round.status != RoundStatus.acceptingAnswers) {
      return null;
    }
    final elapsed =
        Duration(microseconds: game.hostTimeMicros - startedAt) +
        (game.recoveryPaused || !extrapolateTime
            ? Duration.zero
            : now.difference(receivedAt));
    final remaining = question.timeLimit - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Returns a copy with the given fields replaced.
  SpectatorSessionState copyWith({
    QuizClientStatus? status,
    GameState? game,
    String? serverName,
    String? error,
    DateTime? snapshotReceivedAt,
    int? reconnectAttempt,
    bool clearError = false,
    bool? extrapolateTime,
    Uri? mediaBaseUri,
  }) => SpectatorSessionState(
    extrapolateTime: extrapolateTime ?? this.extrapolateTime,
    status: status ?? this.status,
    game: game ?? this.game,
    serverName: serverName ?? this.serverName,
    error: clearError ? null : error ?? this.error,
    snapshotReceivedAt: snapshotReceivedAt ?? this.snapshotReceivedAt,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    mediaBaseUri: mediaBaseUri ?? this.mediaBaseUri,
  );

  @override
  List<Object?> get props => [
    status,
    game,
    serverName,
    error,
    snapshotReceivedAt,
    reconnectAttempt,
    extrapolateTime,
    mediaBaseUri,
  ];
}

/// Drives one TV screen: watch, and keep watching.
///
/// A TV runs unattended for hours, so unlike the player cubit this one never
/// gives up: whenever the socket closes or the host is unreachable it retries
/// with a growing back-off (capped at [maxReconnectDelay]).
class SpectatorSessionCubit extends Cubit<SpectatorSessionState> {
  /// Creates a controller that watches the host at [baseUri].
  SpectatorSessionCubit({
    required this.baseUri,
    QuizClientFactory clientFactory = _defaultClientFactory,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 10),
    DateTime Function() now = DateTime.now,
  }) : _clientFactory = clientFactory,
       _now = now,
       super(const SpectatorSessionState());

  /// Base address of the host.
  final Uri baseUri;

  /// Back-off step between two reconnect attempts.
  final Duration reconnectDelay;

  /// Upper bound of the back-off.
  final Duration maxReconnectDelay;

  final QuizClientFactory _clientFactory;
  final DateTime Function() _now;

  QuizClient? _client;
  StreamSubscription<GameState>? _gameSubscription;
  StreamSubscription<QuizClientStatus>? _statusSubscription;
  StreamSubscription<ProtocolErrorMessage>? _errorSubscription;
  String? _joinCode;

  Future<void> setJoinCode(String code) {
    _joinCode = code;
    return reconnect();
  }

  Timer? _retryTimer;
  var _attempt = 0;

  /// Opens the connection and starts watching.
  Future<void> start() => _connect();

  /// Drops the current connection and connects again right away.
  Future<void> reconnect() {
    _attempt = 0;
    return _connect();
  }

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardown();
    return super.close();
  }

  Future<void> _connect() async {
    if (isClosed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardown();
    if (isClosed) return;

    emit(
      state.copyWith(
        status: QuizClientStatus.connecting,
        reconnectAttempt: _attempt,
        clearError: true,
      ),
    );

    final client = _clientFactory(baseUri);
    _client = client;
    _gameSubscription = client.games.listen(_onSnapshot);
    _statusSubscription = client.statuses.listen(
      (status) => _onStatus(client, status),
    );
    _errorSubscription = client.errors.listen((error) {
      if (isClosed || _client != client) return;
      if (error.code == 'invalidCode') _joinCode = null;
      emit(state.copyWith(error: error.message));
    });

    try {
      await client.watch(joinCode: _joinCode);
    } on Object catch (error) {
      if (isClosed || _client != client) return;
      emit(state.copyWith(status: QuizClientStatus.failed, error: '$error'));
      _scheduleReconnect();
    }
  }

  void _onStatus(QuizClient client, QuizClientStatus status) {
    if (isClosed || _client != client) return;
    emit(state.copyWith(status: status, serverName: client.serverName));
    switch (status) {
      case QuizClientStatus.connected:
        _attempt = 0;
      case QuizClientStatus.disconnected || QuizClientStatus.failed:
        _scheduleReconnect();
      case QuizClientStatus.connecting:
        break;
    }
  }

  void _onSnapshot(GameState game) {
    if (isClosed) return;
    emit(
      state.copyWith(
        game: game,
        snapshotReceivedAt: _now(),
        serverName: _client?.serverName,
        mediaBaseUri: _client?.mediaBaseUri,
      ),
    );
  }

  void _scheduleReconnect() {
    if (isClosed || _retryTimer != null) return;
    _attempt++;
    final delay = reconnectDelay * _attempt;
    _retryTimer = Timer(
      delay > maxReconnectDelay ? maxReconnectDelay : delay,
      () {
        _retryTimer = null;
        unawaited(_connect());
      },
    );
  }

  Future<void> _teardown() async {
    await _gameSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorSubscription?.cancel();
    _gameSubscription = null;
    _statusSubscription = null;
    final client = _client;
    _client = null;
    await client?.dispose();
  }
}
