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

/// Lifecycle of a [QuizClient].
enum QuizClientStatus {
  /// No socket is open.
  disconnected,

  /// The clock handshake or the socket upgrade is in progress.
  connecting,

  /// The socket is open and the join request was accepted.
  connected,

  /// The connection failed; see `QuizClient.lastError`.
  failed,
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
  final StreamController<QuizClientStatus> _statuses =
      StreamController<QuizClientStatus>.broadcast();
  final StreamController<ProtocolErrorMessage> _errors =
      StreamController<ProtocolErrorMessage>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _resyncTimer;
  Completer<void>? _joinCompleter;
  String? _playerId;
  String? _serverName;
  QuizClientStatus _status = QuizClientStatus.disconnected;
  Object? _lastError;

  /// Redacted session snapshots pushed by the host.
  Stream<GameState> get games => _games.stream;

  /// Connection lifecycle updates.
  Stream<QuizClientStatus> get statuses => _statuses.stream;

  /// Protocol level rejections that did not close the socket.
  Stream<ProtocolErrorMessage> get errors => _errors.stream;

  /// Current lifecycle position.
  QuizClientStatus get status => _status;

  /// Server assigned player id, available once the join was accepted.
  String? get playerId => _playerId;

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
    String? resumePlayerId,
    int handshakeProbes = 5,
    Duration joinTimeout = const Duration(seconds: 10),
  }) async {
    await disconnect();
    _emitStatus(QuizClientStatus.connecting);
    _lastError = null;

    try {
      await _handshake(probes: handshakeProbes);

      final channel = WebSocketChannel.connect(_socketUri);
      _channel = channel;
      await channel.ready;

      final joined = Completer<void>();
      _joinCompleter = joined;

      _socketSubscription = channel.stream.listen(
        _onFrame,
        onDone: _onSocketClosed,
        onError: (Object error) {
          _failJoin(error);
          _lastError = error;
          _emitStatus(QuizClientStatus.failed);
        },
      );

      _send(
        JoinRequest(
          name: name,
          teamId: teamId,
          resumePlayerId: resumePlayerId,
          clockOffsetMicros: clock.clockOffsetMicros,
          roundTripMicros: clock.roundTripMicros,
        ),
      );

      await joined.future.timeout(joinTimeout);
      _resyncTimer = Timer.periodic(resyncInterval, (_) => _probeOverSocket());
    } on Object catch (error) {
      _lastError = error;
      _emitStatus(QuizClientStatus.failed);
      rethrow;
    }
  }

  /// Watches the session as a read-only spectator, for example on a TV.
  ///
  /// Unlike [connect] this skips the clock handshake and never creates a
  /// player: the host only streams redacted snapshots to this client, and
  /// [pressBuzzer] / [submitChoice] stay no-ops because [playerId] is `null`.
  Future<void> watch({
    Duration joinTimeout = const Duration(seconds: 10),
  }) async {
    await disconnect();
    _emitStatus(QuizClientStatus.connecting);
    _lastError = null;

    try {
      final channel = WebSocketChannel.connect(_socketUri);
      _channel = channel;
      await channel.ready;

      final accepted = Completer<void>();
      _joinCompleter = accepted;

      _socketSubscription = channel.stream.listen(
        _onFrame,
        onDone: _onSocketClosed,
        onError: (Object error) {
          _failJoin(error);
          _lastError = error;
          _emitStatus(QuizClientStatus.failed);
        },
      );

      _send(const WatchRequest());
      await accepted.future.timeout(joinTimeout);
    } on Object catch (error) {
      _lastError = error;
      _emitStatus(QuizClientStatus.failed);
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

  void submitAnswer(
    AnswerSubmission Function(String playerId, int timestamp, int offset) build,
  ) {
    final id = _playerId;
    if (id == null) return;
    _send(SubmissionMessage(build(id, _now(), clock.clockOffsetMicros)));
  }

  /// Closes the socket and stops the re-sync timer.
  Future<void> disconnect() async {
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
    if (_status != QuizClientStatus.disconnected) {
      _emitStatus(QuizClientStatus.disconnected);
    }
  }

  /// Releases every resource owned by this client.
  Future<void> dispose() async {
    await disconnect();
    if (_ownsHttpClient) _http.close();
    await _games.close();
    await _statuses.close();
    await _errors.close();
  }

  // --------------------------------------------------------------- internals ---

  Uri get _socketUri => baseUri.replace(
    scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
    path: '/ws',
  );

  Future<void> _handshake({required int probes}) async {
    final endpoint = baseUri.replace(path: '/api/sync-time');
    for (var probe = 0; probe < probes; probe++) {
      final sentAt = _now();
      final response = await _http.post(
        endpoint,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'clientSentAtMicros': sentAt}),
      );
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

  void _probeOverSocket() => _send(SyncPing(clientSentAtMicros: _now()));

  void _send(ClientMessage message) => _channel?.sink.add(message.encode());

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    final ServerMessage message;
    try {
      message = ServerMessage.decode(frame);
    } on Object {
      return;
    }

    switch (message) {
      case WelcomeMessage(:final serverName):
        _serverName = serverName;
      case JoinAcceptedMessage(:final playerId):
        _playerId = playerId;
        _joinCompleter?.complete();
        _joinCompleter = null;
        _emitStatus(QuizClientStatus.connected);
      case WatchAcceptedMessage():
        _joinCompleter?.complete();
        _joinCompleter = null;
        _emitStatus(QuizClientStatus.connected);
      case SyncPong(:final clientSentAtMicros, :final hostTimeMicros):
        clock.add(
          ClockSample(
            clientSentAtMicros: clientSentAtMicros,
            hostTimeMicros: hostTimeMicros,
            clientReceivedAtMicros: _now(),
          ),
        );
        _send(
          ClockReport(
            clockOffsetMicros: clock.clockOffsetMicros,
            roundTripMicros: clock.roundTripMicros,
          ),
        );
      case GameSnapshotMessage(:final game):
        if (!_games.isClosed) _games.add(game);
      case ProtocolErrorMessage():
        if (!_errors.isClosed) _errors.add(message);
    }
  }

  void _onSocketClosed() {
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _channel = null;
    _failJoin(StateError('The host closed the connection.'));
    if (_status != QuizClientStatus.disconnected) {
      _emitStatus(QuizClientStatus.disconnected);
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
