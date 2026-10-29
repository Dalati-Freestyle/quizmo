/// The pure Dart player client.
///
/// Runs unchanged on Flutter Web, Android, iOS and desktop: it only depends on
/// `package:http` and `package:web_socket_channel`, never on `dart:io`.
///
/// ## Connection sequence
///
/// 1. `POST /api/sync-time` a handful of times to measure the clock offset.
/// 2. Upgrade to `ws://host:port/ws`.
/// 3. Send a [JoinRequest] carrying the measured offset.
/// 4. Keep re-probing the clock over the socket so drift cannot accumulate.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../protocol/messages.dart';
import '../sync/clock.dart';
import '../sync/clock_sync.dart';
import 'session_uri.dart';

/// Lifecycle of a [QuizClient].
enum QuizClientStatus {
  /// No socket is open.
  disconnected,

  /// The clock handshake or the socket upgrade is in progress.
  connecting,

  /// The socket is open and the join request was accepted.
  connected,

  reconnecting,

  closed,

  /// The connection failed; see `QuizClient.lastError`.
  failed,
}

final class JoinRejectedException extends StateError {
  JoinRejectedException(this.code, String message) : super(message);
  final String code;
  @override
  String toString() => message;
}

/// Talks to an embedded quiz host.
class QuizClient {
  /// Creates a client for the host reachable at [baseUri].
  QuizClient({
    required this.baseUri,
    http.Client? httpClient,
    NowMicros now = systemNowMicros,
    this.resyncInterval = const Duration(seconds: 10),
  }) : _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _now = now,
       clock = ClockSyncEstimator(now: now);

  /// Base address of the host, for example `http://192.168.1.42:8080`.
  final Uri baseUri;

  /// How often the clock probe is repeated over the open socket.
  final Duration resyncInterval;

  /// Live clock offset estimate against the host.
  final ClockSyncEstimator clock;

  final http.Client _http;
  final bool _ownsHttpClient;
  final NowMicros _now;

  final StreamController<GameState> _games =
      StreamController<GameState>.broadcast();
  final _snapshots = StreamController<GameSnapshotMessage>.broadcast();
  Stream<GameSnapshotMessage> get snapshots => _snapshots.stream;
  final StreamController<QuizClientStatus> _statuses =
      StreamController<QuizClientStatus>.broadcast();
  final StreamController<ProtocolErrorMessage> _errors =
      StreamController<ProtocolErrorMessage>.broadcast();
  final StreamController<LobbySnapshotMessage> _lobbies =
      StreamController<LobbySnapshotMessage>.broadcast();
  bool _inLobby = false;
  bool _awaitingLobby = false;
  bool _awaitingApproval = false;
  final _admissions = StreamController<bool>.broadcast();
  Stream<bool> get admissions => _admissions.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _resyncTimer;
  Completer<void>? _joinCompleter;
  String? _playerId;
  String? _resumeToken;
  String? _accessToken;
  Uri get mediaBaseUri => _accessToken == null
      ? baseUri
      : baseUri.replace(
          queryParameters: {
            ...baseUri.queryParameters,
            'access': _accessToken!,
          },
        );
  int _lastFrameAt = 0;
  String? _serverName;
  QuizClientStatus _status = QuizClientStatus.disconnected;
  Object? _lastError;
  bool _disposed = false;
  int _connectionGeneration = 0;
  Completer<void>? _syncProbe;

  /// Redacted session snapshots pushed by the host.
  Stream<GameState> get games => _games.stream;

  /// Connection lifecycle updates.
  Stream<QuizClientStatus> get statuses => _statuses.stream;

  /// Protocol level rejections that did not close the socket.
  Stream<ProtocolErrorMessage> get errors => _errors.stream;
  Stream<LobbySnapshotMessage> get lobbies => _lobbies.stream;

  /// Current lifecycle position.
  QuizClientStatus get status => _status;

  /// Server assigned player id, available once the join was accepted.
  String? get playerId => _playerId;
  String? get resumeToken => _resumeToken;

  /// Friendly name reported by the host.
  String? get serverName => _serverName;

  /// Why the last connection attempt failed.
  Object? get lastError => _lastError;

  /// The current instant, projected onto the host timeline.
  int get hostNowMicros => clock.hostNowMicros;

  /// Performs the handshake and joins the session as [name].
  ///
  /// Completes once the host confirmed the join, so [playerId] is guaranteed to
  /// be available afterwards.
  ///
  /// [handshakeProbes] controls how many HTTP round trips are used to seed the
  /// clock estimate; more probes mean a better chance of catching one that was
  /// not delayed by queueing.
  Future<void> connect({
    required String name,
    String? teamId,
    String? newTeamName,
    String? resumePlayerId,
    String? resumeToken,
    String? joinCode,
    int handshakeProbes = 5,
    Duration joinTimeout = const Duration(seconds: 10),
  }) async {
    if (_disposed) throw StateError('This client has been disposed.');
    final joiningFromLobby = _inLobby && _channel != null;
    if (!joiningFromLobby) await disconnect();
    final generation = _connectionGeneration;
    _emitStatus(QuizClientStatus.connecting);
    _lastError = null;
    clock.reset();

    try {
      if (isInternetSession(baseUri)) {
        if (!joiningFromLobby) await _openSocket();
        for (var i = 0; i < handshakeProbes; i++) {
          final probe = Completer<void>();
          _syncProbe = probe;
          _send(SyncPing(clientSentAtMicros: _now()));
          await probe.future.timeout(const Duration(seconds: 5));
          _checkAttempt(generation);
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      } else {
        await _handshake(probes: handshakeProbes);
        _checkAttempt(generation);
        if (!joiningFromLobby) await _openSocket();
      }
      _checkAttempt(generation);
      final joined = Completer<void>();
      _joinCompleter = joined;

      _send(
        JoinRequest(
          name: name,
          teamId: teamId,
          newTeamName: newTeamName,
          resumePlayerId: resumePlayerId,
          resumeToken: resumeToken,
          joinCode: joinCode,
          clockOffsetMicros: clock.clockOffsetMicros,
          roundTripMicros: clock.roundTripMicros,
        ),
      );

      await joined.future.timeout(
        joinTimeout,
        onTimeout: () {
          if (_awaitingApproval) return joined.future;
          throw TimeoutException('The host did not answer the join request.');
        },
      );
      _checkAttempt(generation);
      _resyncTimer = Timer.periodic(resyncInterval, (_) => _probeOverSocket());
    } on Object catch (error) {
      if (generation != _connectionGeneration || _disposed) rethrow;
      _lastError = error;
      if (!_inLobby) await disconnect();
      _emitStatus(
        error is JoinRejectedException && error.code == 'hostClosed'
            ? QuizClientStatus.closed
            : _inLobby && _channel != null
            ? QuizClientStatus.connected
            : QuizClientStatus.failed,
      );
      rethrow;
    }
  }

  Future<void> browseLobby({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await disconnect();
    _emitStatus(QuizClientStatus.connecting);
    _lastError = null;
    try {
      await _openSocket();
      final accepted = Completer<void>();
      _joinCompleter = accepted;
      _inLobby = true;
      _awaitingLobby = true;
      _send(const LobbyRequest());
      await accepted.future.timeout(timeout);
    } on Object catch (error) {
      _lastError = error;
      await disconnect();
      _emitStatus(
        error is JoinRejectedException && error.code == 'hostClosed'
            ? QuizClientStatus.closed
            : QuizClientStatus.failed,
      );
      rethrow;
    }
  }

  void renameTeam(String name) {
    if (_playerId == null) return;
    _send(RenameTeamMessage(name: name));
  }

  /// Watches the session as a read-only spectator, for example on a TV.
  ///
  /// Unlike [connect] this skips the clock handshake and never creates a
  /// player: the host only streams redacted snapshots to this client, and
  /// [pressBuzzer] / [submitChoice] stay no-ops because [playerId] is `null`.
  Future<void> watch({
    String? joinCode,
    Duration joinTimeout = const Duration(seconds: 10),
  }) async {
    await disconnect();
    _emitStatus(QuizClientStatus.connecting);
    _lastError = null;

    try {
      await _openSocket();

      final accepted = Completer<void>();
      _joinCompleter = accepted;

      _send(WatchRequest(joinCode: joinCode));
      await accepted.future.timeout(joinTimeout);
      _resyncTimer = Timer.periodic(resyncInterval, (_) => _probeOverSocket());
    } on Object catch (error) {
      _lastError = error;
      await disconnect();
      _emitStatus(
        error is JoinRejectedException && error.code == 'hostClosed'
            ? QuizClientStatus.closed
            : QuizClientStatus.failed,
      );
      rethrow;
    }
  }

  /// Sends a buzzer press for [questionId].
  ///
  /// The press is stamped with the *local* clock; the host timeline value is
  /// derived from `clientTimestamp - clockOffset` (architecture Rule 3).
  void pressBuzzer(String questionId) {
    final id = _playerId;
    if (id == null) return;
    _send(
      SubmissionMessage(
        BuzzerPress(
          playerId: id,
          questionId: questionId,
          clientTimestampMicros: _now(),
          clockOffsetMicros: clock.clockOffsetMicros,
        ),
      ),
    );
  }

  /// Sends the choice [optionId] for [questionId].
  void submitChoice({required String questionId, required String optionId}) {
    final id = _playerId;
    if (id == null) return;
    _send(
      SubmissionMessage(
        MultipleChoiceAnswer(
          playerId: id,
          questionId: questionId,
          clientTimestampMicros: _now(),
          clockOffsetMicros: clock.clockOffsetMicros,
          optionId: optionId,
        ),
      ),
    );
  }

  void selectJeopardyCell(String questionId) =>
      _send(JeopardyPickMessage(questionId));
  void placeDailyDoubleWager(String questionId, int wager) =>
      _send(DailyDoubleWagerMessage(questionId: questionId, wager: wager));

  void placePokerWager({required String questionId, required int wager}) {
    if (_playerId == null) return;
    _send(PokerWagerMessage(questionId: questionId, wager: wager));
  }

  void submitAnswer(
    AnswerSubmission Function(String playerId, int timestamp, int offset) build,
  ) {
    final id = _playerId;
    if (id == null) return;
    _send(SubmissionMessage(build(id, _now(), clock.clockOffsetMicros)));
  }

  /// Closes the socket and stops the re-sync timer.
  Future<void> disconnect() async {
    _connectionGeneration++;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _failJoin(StateError('The connection was closed while joining.'));

    final channel = _channel;
    if (channel != null) {
      try {
        _send(const LeaveNotice());
        await channel.sink.close();
      } on Object {
        // The socket is already gone; nothing left to clean up remotely.
      }
    }
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel = null;
    _playerId = null;
    _accessToken = null;
    _inLobby = false;
    _awaitingLobby = false;
    _awaitingApproval = false;
    if (!_admissions.isClosed) _admissions.add(false);
    if (_status != QuizClientStatus.disconnected) {
      _emitStatus(QuizClientStatus.disconnected);
    }
  }

  /// Releases every resource owned by this client.
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    if (_ownsHttpClient) _http.close();
    await _games.close();
    await _snapshots.close();
    await _statuses.close();
    await _errors.close();
    await _lobbies.close();
    await _admissions.close();
  }

  // --------------------------------------------------------------- internals ---

  Uri get _socketUri => sessionSocketUri(baseUri);

  Future<void> _openSocket() async {
    if (_disposed) throw StateError('This client has been disposed.');
    final generation = _connectionGeneration;
    if (isInternetSession(baseUri)) {
      final response = await _http
          .get(
            sessionUri(baseUri)
                .replace(path: '${sessionUri(baseUri).path}/status'),
          )
          .timeout(const Duration(seconds: 5));
      _checkAttempt(generation);
      if (response.statusCode == 410) {
        final payload = jsonDecode(response.body);
        if (payload is Map<String, dynamic> &&
            payload['service'] == 'quizmo-room' &&
            payload['open'] == false) {
          throw JoinRejectedException(
            'hostClosed',
            'The host has closed this room. Join a new room to continue.',
          );
        }
      }
    }
    final channel = WebSocketChannel.connect(_socketUri);
    _channel = channel;
    await channel.ready.timeout(const Duration(seconds: 5));
    _checkAttempt(generation);
    _socketSubscription = channel.stream.listen(
      (frame) {
        if (_channel == channel) _onFrame(frame);
      },
      onDone: () {
        if (_channel == channel) _onSocketClosed();
      },
      onError: (Object error) {
        if (_channel != channel) return;
        _failJoin(error);
        _lastError = error;
        _emitStatus(QuizClientStatus.failed);
      },
    );
  }

  void _checkAttempt(int generation) {
    if (_disposed || generation != _connectionGeneration) {
      throw StateError('The connection attempt was cancelled.');
    }
  }

  Future<void> _handshake({required int probes}) async {
    final generation = _connectionGeneration;
    final endpoint = baseUri.replace(path: '/api/sync-time');
    for (var probe = 0; probe < probes; probe++) {
      final sentAt = _now();
      final response = await _http
          .post(
            endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'clientSentAtMicros': sentAt}),
          )
          .timeout(const Duration(seconds: 5));
      _checkAttempt(generation);
      final receivedAt = _now();
      if (response.statusCode != 200) {
        throw StateError('Clock sync failed with HTTP ${response.statusCode}.');
      }
      clock.add(
        ClockSample.fromResponse(
          jsonDecode(response.body) as JsonMap,
          clientReceivedAtMicros: receivedAt,
        ),
      );
      // A short pause spreads the probes over different queueing conditions.
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _probeOverSocket() {
    unawaited(checkConnection());
  }

  Future<void> checkConnection() async {
    if (_status != QuizClientStatus.connected) return;
    final channel = _channel;
    if (_now() - _lastFrameAt <= const Duration(seconds: 30).inMicroseconds) {
      try {
        _send(SyncPing(clientSentAtMicros: _now()));
        return;
      } on StateError catch (error) {
        _lastError = error;
      }
    }
    _onSocketClosed();
    await channel?.sink.close();
  }

  void _send(ClientMessage message) {
    final channel = _channel;
    if (channel == null) throw StateError('No connection to the host.');
    channel.sink.add(message.encode());
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    _lastFrameAt = _now();
    final ServerMessage message;
    try {
      message = ServerMessage.decode(frame);
    } on Object {
      return;
    }

    switch (message) {
      case WelcomeMessage(:final serverName):
        _serverName = serverName;
      case JoinAcceptedMessage(
        :final playerId,
        :final resumeToken,
        :final accessToken,
      ):
        _accessToken = accessToken;
        _awaitingApproval = false;
        _admissions.add(false);
        _inLobby = false;
        _playerId = playerId;
        _resumeToken = resumeToken;
        _joinCompleter?.complete();
        _joinCompleter = null;
        _emitStatus(QuizClientStatus.connected);
      case WatchAcceptedMessage(:final accessToken):
        _accessToken = accessToken;
        _joinCompleter?.complete();
        _joinCompleter = null;
        _emitStatus(QuizClientStatus.connected);
      case AdmissionPendingMessage():
        _awaitingApproval = true;
        _admissions.add(true);
      case LobbySnapshotMessage():
        if (!_lobbies.isClosed) _lobbies.add(message);
        if (_awaitingLobby) {
          _awaitingLobby = false;
          _joinCompleter?.complete();
          _joinCompleter = null;
          _emitStatus(QuizClientStatus.connected);
        }
      case SyncPong(:final clientSentAtMicros, :final hostTimeMicros):
        clock.add(
          ClockSample(
            clientSentAtMicros: clientSentAtMicros,
            hostTimeMicros: hostTimeMicros,
            clientReceivedAtMicros: _now(),
          ),
        );
        final probe = _syncProbe;
        _syncProbe = null;
        if (probe != null && !probe.isCompleted) probe.complete();
        _send(
          ClockReport(
            clockOffsetMicros: clock.clockOffsetMicros,
            roundTripMicros: clock.roundTripMicros,
          ),
        );
      case GameSnapshotMessage(:final game):
        if (!_games.isClosed) _games.add(game);
        if (!_snapshots.isClosed) _snapshots.add(message);
      case ProtocolErrorMessage():
        _awaitingApproval = false;
        _admissions.add(false);
        if (!_errors.isClosed) _errors.add(message);
        _failJoin(JoinRejectedException(message.code, message.message));
        if (message.code == 'hostClosed') {
          _resyncTimer?.cancel();
          _emitStatus(QuizClientStatus.closed);
        }
    }
  }

  void _onSocketClosed() {
    final roomClosed =
        _channel?.closeCode == 3001 || _status == QuizClientStatus.closed;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _channel = null;
    _failJoin(StateError('The host closed the connection.'));
    if (_status != QuizClientStatus.disconnected) {
      _emitStatus(
        roomClosed ? QuizClientStatus.closed : QuizClientStatus.disconnected,
      );
    }
  }

  /// Aborts a pending join so `connect` does not hang on a dead socket.
  void _failJoin(Object error) {
    final completer = _joinCompleter;
    _joinCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void _emitStatus(QuizClientStatus status) {
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }
}
