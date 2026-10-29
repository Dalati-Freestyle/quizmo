/// Web socket hub of the embedded host.
///
/// Owns the open connections, translates inbound [ClientMessage]s into
/// [QuizEngineEvent]s and pushes every engine transition back to the clients as
/// a redacted [GameSnapshotMessage].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/engine/session_access.dart';
import '../../core/data/session_recovery.dart';
import '../../core/models/models.dart';
import '../../core/protocol/messages.dart';
import '../../core/sync/clock.dart';
import '../server_contract.dart';
import 'socket_upgrade.dart';

/// One open web socket, possibly not joined yet.
final class _Connection {
  _Connection({
    required this.id,
    required this.sendFrame,
    required this.closeSocket,
  });

  final String id;
  final void Function(String) sendFrame;
  final Future<void> Function() closeSocket;
  StreamSubscription<dynamic>? subscription;
  int windowStart = 0;
  int frames = 0;
  Timer? handshakeTimeout;
  Timer? identityRetry;

  /// Authoritative player id; `null` until the join request was accepted.
  String? playerId;

  /// Whether this socket only watches (TV screen); it never owns a player.
  bool isSpectator = false;
  bool isLobby = false;
  JoinRequest? pendingJoin;
  int failedCodes = 0;
  String? spectatorCodeHash;

  void send(ServerMessage message) {
    try {
      sendFrame(message.encode());
    } on Object {
      // Losing a frame on a dying socket is not worth tearing the hub down.
    }
  }
}

/// Bridges web socket traffic and the [QuizEngineBloc].
class SocketHub {
  /// Creates a hub for [engine].
  SocketHub({
    required QuizEngineBloc engine,
    required this.serverName,
    NowMicros now = systemNowMicros,
    void Function(ServerLogEntry entry)? onLog,
  }) : _engine = engine,
       _now = now,
       _onLog = onLog {
    _knownPlayerIds = _engine.state.game.players.keys.toSet();
    _engineSubscription = _engine.stream.listen(_broadcastState);
    _accessSubscription = _engine.access.stream.listen(_accessChanged);
  }

  /// Friendly name announced to every client.
  final String serverName;

  final QuizEngineBloc _engine;
  final NowMicros _now;
  final void Function(ServerLogEntry entry)? _onLog;
  final Map<String, _Connection> _connections = <String, _Connection>{};

  StreamSubscription<QuizEngineState>? _engineSubscription;
  StreamSubscription<SessionAccessState>? _accessSubscription;
  int _codeWindowStart = 0;
  int _failedCodes = 0;
  var _nextConnectionId = 0;
  Map<String, String> get _resumeTokens => _engine.resumeTokenHashes;
  final Map<String, String> _activeTokens = {};
  final Set<String> _pendingPlayerIds = {};
  Set<String> _knownPlayerIds = {};
  int _broadcastRevision = 0;

  /// Number of open sockets.
  int get connectionCount => _connections.length;

  /// The shelf handler that performs the web socket upgrade.
  Handler get handler => createSocketUpgradeHandler(
    (WebSocketChannel channel, String? protocol) => _onConnected(channel),
  );

  /// Attaches an isolated transport, including a virtual relay connection.
  void attach({
    required Stream<dynamic> stream,
    required void Function(String) send,
    required Future<void> Function() close,
  }) => _attach(stream, send, close);

  /// Closes every socket and stops listening to the engine.
  Future<void> close() async {
    await _accessSubscription?.cancel();
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    final connections = _connections.values.toList(growable: false);
    _connections.clear();
    for (final connection in connections) {
      _engine.access.revokeReadCredential(connection.id);
      connection.handshakeTimeout?.cancel();
      connection.identityRetry?.cancel();
      _engine.access.forget(connection.id);
      await connection.subscription?.cancel();
      await connection.closeSocket();
    }
  }

  // --------------------------------------------------------------- internals ---

  void _onConnected(WebSocketChannel channel) {
    _attach(channel.stream, (frame) => channel.sink.add(frame), () async {
      await channel.sink.close();
    });
  }

  void _attach(
    Stream<dynamic> stream,
    void Function(String) send,
    Future<void> Function() close,
  ) {
    if (_connections.length >= 128) {
      close();
      return;
    }
    final connection = _Connection(
      id: 'conn-${_nextConnectionId++}',
      sendFrame: send,
      closeSocket: close,
    );
    _connections[connection.id] = connection;
    _log(ServerLogLevel.info, 'Socket ${connection.id} connected.');

    connection.send(
      WelcomeMessage(
        connectionId: connection.id,
        hostTimeMicros: _now(),
        serverName: serverName,
      ),
    );

    connection.subscription = stream.listen(
      (Object? frame) => _onFrame(connection, frame),
      onDone: () => _onDisconnected(connection),
      onError: (Object error) {
        _log(
          ServerLogLevel.warning,
          'Socket ${connection.id}: transport error.',
        );
        _onDisconnected(connection);
      },
      cancelOnError: true,
    );
    connection.handshakeTimeout = Timer(const Duration(seconds: 15), () {
      if (connection.playerId == null &&
          !connection.isSpectator &&
          !connection.isLobby &&
          connection.pendingJoin == null) {
        _onDisconnected(connection);
        connection.closeSocket();
      }
    });
  }

  Future<void> _onFrame(
    _Connection connection,
    Object? frame, {
    bool approved = false,
  }) async {
    if (!_connections.containsKey(connection.id)) return;
    final identity = connection.playerId;
    if (identity != null &&
        (!_resumeTokens.containsKey(identity) ||
            _engine.access.state.bannedPlayerIds.contains(identity))) {
      _reject(
        connection,
        'kicked',
        'You were removed from this session.',
        close: true,
      );
      return;
    }
    if (frame is! String ||
        frame.length > 65536 ||
        utf8.encode(frame).length > 65536) {
      _onDisconnected(connection);
      connection.closeSocket();
      return;
    }
    final now = _now();
    if (now - connection.windowStart >= 1000000) {
      connection.windowStart = now;
      connection.frames = 0;
    }
    if (++connection.frames > 60) {
      _onDisconnected(connection);
      connection.closeSocket();
      return;
    }

    final ClientMessage message;
    try {
      message = ClientMessage.decode(frame);
    } on Object {
      connection.send(
        const ProtocolErrorMessage(
          code: 'badRequest',
          message: 'Invalid message.',
        ),
      );
      return;
    }

    switch (message) {
      case JoinRequest(
        :final name,
        :final teamId,
        :final newTeamName,
        :final resumePlayerId,
        :final resumeToken,
        :final clockOffsetMicros,
        :final roundTripMicros,
      ):
        if (connection.playerId != null || connection.isSpectator) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'alreadyJoined',
              message: 'This connection has already joined.',
            ),
          );
          return;
        }
        if (connection.pendingJoin != null) {
          connection.send(const AdmissionPendingMessage());
          return;
        }
        final game = _engine.state.game;
        final policy = _engine.access.state;
        if (resumePlayerId == null && resumeToken != null) {
          _reject(
            connection,
            'invalidResume',
            'Diese Spieler-Sitzung ist nicht mehr verfügbar. Bitte neu beitreten.',
          );
          return;
        }
        if (resumePlayerId != null &&
            policy.bannedPlayerIds.contains(resumePlayerId)) {
          _reject(
            connection,
            'banned',
            'This participant is banned for this session.',
            close: true,
          );
          return;
        }
        if (newTeamName != null &&
            game.recoveryPaused &&
            _engine.recoveryPlayerIds.isNotEmpty) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidTeam',
              message: 'During recovery, choose an existing team. The host can reassign your original identity.',
            ),
          );
          return;
        }
        if ((resumePlayerId == null &&
                game.players.length + _pendingPlayerIds.length >= 256) ||
            roundTripMicros < 0 ||
            roundTripMicros > 30000000) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'joinLimit',
              message: 'The roster is full or the clock handshake is invalid. Ask the host to remove unused players.',
            ),
          );
          return;
        }
        if (name.trim().isEmpty ||
            name.trim().length > 60 ||
            (newTeamName != null &&
                (newTeamName.trim().isEmpty ||
                    newTeamName.trim().length > 60 ||
                    teamId != null))) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidName',
              message: 'Names must contain 1 to 60 characters. Choose an existing team or create one.',
            ),
          );
          return;
        }
        final returning = game.players[resumePlayerId];
        if (resumePlayerId != null &&
            (returning == null ||
                resumeToken == null ||
                _resumeTokens[resumePlayerId] !=
                    hashResumeToken(resumeToken))) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidResume',
              message: 'Diese Spieler-Sitzung ist nicht mehr verfügbar. Bitte neu beitreten.',
            ),
          );
          return;
        }
        if (returning == null) {
          if (policy.locked) {
            _reject(
              connection,
              'lobbyLocked',
              'The lobby is locked. Existing players can still reconnect.',
            );
            return;
          }
          if (!_checkCode(connection, message.joinCode)) return;
        }
        if (returning == null &&
            ((teamId != null && !game.teams.containsKey(teamId)) ||
                (game.poker != null &&
                    teamId == null &&
                    newTeamName == null))) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidTeam',
              message: 'Choose an available team or create a new one.',
            ),
          );
          return;
        }
        final createdTeam = newTeamName == null
            ? null
            : Team(id: newId('team'), name: newTeamName.trim());
        if (createdTeam != null &&
            resumePlayerId != null &&
            game.players.containsKey(resumePlayerId)) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidTeam',
              message: 'A returning player cannot create another team.',
            ),
          );
          return;
        }
        if (returning == null && policy.requireApproval && !approved) {
          connection.pendingJoin = message;
          connection.isLobby = false;
          connection.handshakeTimeout?.cancel();
          _engine.access.request(connection.id, name.trim());
          connection.send(const AdmissionPendingMessage());
          return;
        }
        final playerId = resumePlayerId ?? newId('player');
        // Retire a stale socket before assigning its identity to the new one.
        for (final old in _connections.values.toList()) {
          if (old.playerId != playerId) continue;
          old.send(
            const ProtocolErrorMessage(
              code: 'sessionReplaced',
              message: 'Deine Sitzung wurde auf einem anderen Fenster oder Gerät fortgesetzt.',
            ),
          );
          old.playerId = null;
          _engine.access.revokeReadCredential(old.id);
          old.handshakeTimeout?.cancel();
          _connections.remove(old.id);
          old.subscription?.cancel();
          old.closeSocket();
        }
        final token = returning != null
            ? resumeToken!
            : base64UrlEncode(
                List<int>.generate(32, (_) => Random.secure().nextInt(256)),
              );
        _resumeTokens[playerId] = hashResumeToken(token);
        _activeTokens[playerId] = token;
        connection.playerId = playerId;
        connection.isLobby = false;
        if (returning == null) _pendingPlayerIds.add(playerId);
        final joined = returning?.isConnected == true
            ? null
            : _engine.stream.firstWhere(
                (s) => s.game.players[playerId]?.isConnected == true,
              );
        _engine.add(
          PlayerJoinedEvent(
            Player(
              id: playerId,
              name: returning?.name ?? name.trim(),
              teamId: returning?.teamId ?? createdTeam?.id ?? teamId,
              clockOffsetMicros: clockOffsetMicros,
              roundTripMicros: roundTripMicros,
            ),
            createdTeam: createdTeam,
          ),
        );
        if (joined != null) {
          await joined;
        } else {
          await Future<void>.delayed(Duration.zero);
        }
        try {
          await _engine.persistRecovery?.call();
        } on Object {
          connection.send(
            const ProtocolErrorMessage(
              code: 'recoveryUnavailable',
              message: 'Joining could not be saved. Ask the host to retry recovery storage.',
            ),
          );
          _onDisconnected(connection);
          await connection.closeSocket();
          return;
        }
        if (!_connections.containsKey(connection.id) ||
            connection.playerId != playerId) {
          return;
        }
        connection.send(
          JoinAcceptedMessage(
            playerId: playerId,
            hostTimeMicros: _now(),
            resumeToken: token,
            accessToken: _engine.access.issueReadCredential(connection.id),
          ),
        );
        connection.send(
          GameSnapshotMessage(_engine.publishedGame.redactedForPlayers()),
        );
        _log(ServerLogLevel.info, 'Participant $playerId joined.');

      case LobbyRequest():
        if (connection.playerId != null || connection.isSpectator) return;
        if (connection.pendingJoin != null) {
          connection.send(const AdmissionPendingMessage());
          return;
        }
        connection.isLobby = true;
        connection.send(_lobbySnapshot());

      case RenameTeamMessage(:final name):
        final player = _engine.state.game.players[connection.playerId];
        if (player?.teamId == null || connection.isSpectator) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'notInTeam',
              message: 'Join a team before renaming it.',
            ),
          );
          return;
        }
        if (name.trim().isEmpty || name.trim().length > 60) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidName',
              message: 'Team names must contain 1 to 60 characters.',
            ),
          );
          return;
        }
        _engine.add(RenameTeamEvent(playerId: player!.id, name: name));

      case WatchRequest(:final joinCode):
        if (connection.playerId != null ||
            connection.isLobby ||
            connection.pendingJoin != null) {
          return;
        }
        if (!_engine.access.state.allowSpectators) {
          _reject(
            connection,
            'spectatorsDisabled',
            'Spectator access is disabled by the host.',
            close: true,
          );
          return;
        }
        if (!_checkCode(connection, joinCode)) return;
        // Spectators are deliberately anonymous: no roster entry, no clock
        // sync and no way to submit, so a TV can never influence a round.
        connection.isSpectator = true;
        connection.spectatorCodeHash = _engine.access.state.codeHash;
        connection.send(
          WatchAcceptedMessage(
            accessToken: _engine.access.issueReadCredential(connection.id),
          ),
        );
        connection.send(
          GameSnapshotMessage(_engine.publishedGame.redactedForPlayers()),
        );
        _log(ServerLogLevel.info, 'Spectator ${connection.id} is watching.');

      case SyncPing(:final clientSentAtMicros):
        // Stamped last so that parsing cost is not attributed to the network.
        connection.send(
          SyncPong(
            clientSentAtMicros: clientSentAtMicros,
            hostTimeMicros: _now(),
          ),
        );

      case ClockReport(:final clockOffsetMicros, :final roundTripMicros):
        if (roundTripMicros < 0 || roundTripMicros > 30000000) return;
        final playerId = connection.playerId;
        if (playerId == null) return;
        _engine.add(
          TimeSyncEvent(
            playerId: playerId,
            clockOffsetMicros: clockOffsetMicros,
            roundTripMicros: roundTripMicros,
          ),
        );

      case SubmissionMessage(:final submission):
        final playerId = connection.playerId;
        if (playerId == null) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'notJoined',
              message: 'Send a join request before submitting.',
            ),
          );
          return;
        }
        // Never trust the client's self reported identity.
        final trusted = submission.withPlayerId(playerId);
        final now = _now();
        final startedAt = _engine.state.game.round.startedAtHostMicros;
        if (trusted.hostTimestampMicros > now + 250000 ||
            trusted.hostTimestampMicros < now - 30000000 ||
            (startedAt != null && trusted.hostTimestampMicros < startedAt)) {
          connection.send(
            const ProtocolErrorMessage(
              code: 'invalidTimestamp',
              message: 'Submission timestamp is outside the current round. Resync your clock.',
            ),
          );
          return;
        }
        switch (trusted) {
          case MultipleChoiceAnswer() ||
              ShortAnswer() ||
              OrderingAnswer() ||
              MatchingAnswer() ||
              EstimationAnswer() ||
              TrueFalseAnswer():
            _engine.add(SubmitAnswerEvent(trusted));
          case BuzzerPress():
            _engine.add(BuzzerPressEvent(trusted));
        }

      case JeopardyPickMessage(:final questionId):
        final id = connection.playerId;
        if (id == null || connection.isSpectator) return;
        _engine.add(SelectJeopardyCellEvent(questionId, playerId: id));
      case DailyDoubleWagerMessage(:final questionId, :final wager):
        final id = connection.playerId;
        if (id == null || connection.isSpectator) return;
        _engine.add(
          PlaceDailyDoubleWagerEvent(
            wager,
            playerId: id,
            questionId: questionId,
          ),
        );
      case PokerWagerMessage(:final questionId, :final wager):
        final playerId = connection.playerId;
        if (playerId == null || connection.isSpectator) return;
        _engine.add(
          PlacePokerWagerEvent(
            playerId: playerId,
            questionId: questionId,
            wager: wager,
          ),
        );

      case LeaveNotice():
        _onDisconnected(connection);
        connection.closeSocket();
    }
  }

  void _onDisconnected(_Connection connection) {
    if (_connections.remove(connection.id) == null) return;
    _engine.access.revokeReadCredential(connection.id);
    connection.handshakeTimeout?.cancel();
    connection.identityRetry?.cancel();
    connection.subscription?.cancel();
    _engine.access.forget(connection.id);
    final playerId = connection.playerId;
    if (playerId != null &&
        !_connections.values.any((c) => c.playerId == playerId)) {
      _engine.add(PlayerLeftEvent(playerId));
    }
    _log(ServerLogLevel.info, 'Socket ${connection.id} disconnected.');
  }

  void _broadcastState(QuizEngineState state) {
    _pendingPlayerIds.removeWhere(state.game.players.containsKey);
    final removed = _knownPlayerIds.difference(state.game.players.keys.toSet());
    _knownPlayerIds = state.game.players.keys.toSet();
    for (final connection in _connections.values.toList()) {
      final oldId = connection.playerId;
      final reboundId = _engine.identityTransfers[oldId];
      final token = _activeTokens[oldId];
      if (reboundId != null && token != null && removed.contains(oldId)) {
        connection.playerId = reboundId;
        _activeTokens[reboundId] = token;
        unawaited(_completeRebind(connection, reboundId, token));
      }
    }
    for (final id in removed) {
      _resumeTokens.remove(id);
      _activeTokens.remove(id);
    }
    // Revoke transport authority before persistence or another inbound frame.
    for (final connection in _connections.values.toList()) {
      if (connection.playerId != null &&
          removed.contains(connection.playerId)) {
        final banned = _engine.access.state.bannedPlayerIds.contains(
          connection.playerId,
        );
        connection.playerId = null;
        _reject(
          connection,
          banned ? 'banned' : 'kicked',
          banned
              ? 'This participant is banned for this session.'
              : 'You were removed. Joining again requires a new admission.',
          close: true,
        );
      }
    }
    if (_connections.isEmpty) return;
    unawaited(_broadcastCommitted(++_broadcastRevision));
  }

  Future<void> _broadcastCommitted(int revision) async {
    try {
      await _engine.persistRecovery?.call();
    } on Object {
      if (revision == _broadcastRevision) {
        for (final connection in _connections.values.toList()) {
          if (connection.playerId != null || connection.isSpectator) {
            connection.send(
              GameSnapshotMessage(_engine.publishedGame.redactedForPlayers()),
            );
          }
          connection.send(
            const ProtocolErrorMessage(
              code: 'recoveryUnavailable',
              message: 'Recovery could not be saved. Check free space and storage permissions; the last successful save is retained. Retry before continuing.',
            ),
          );
        }
      }
      return;
    }
    if (revision != _broadcastRevision || _connections.isEmpty) return;
    final game = _engine.publishedGame;
    final message = GameSnapshotMessage(game.redactedForPlayers());
    for (final connection in _connections.values.toList(growable: false)) {
      if (connection.playerId != null &&
          !game.players.containsKey(connection.playerId)) {
        connection.send(
          const ProtocolErrorMessage(
            code: 'kicked',
            message: 'Der Spielleiter hat dich aus der Sitzung entfernt.',
          ),
        );
        connection.playerId = null;
        _onDisconnected(connection);
        connection.closeSocket();
        continue;
      }
      if (connection.isLobby) {
        connection.send(_lobbySnapshot());
      } else if (connection.playerId != null || connection.isSpectator) {
        connection.send(message);
      }
    }
  }

  Future<void> _completeRebind(
    _Connection connection,
    String id,
    String token,
  ) async {
    connection.identityRetry?.cancel();
    try {
      await _engine.persistRecovery?.call();
      if (!_connections.containsKey(connection.id)) return;
      connection.send(
        JoinAcceptedMessage(
          playerId: id,
          hostTimeMicros: _now(),
          resumeToken: token,
          accessToken: _engine.access.issueReadCredential(connection.id),
        ),
      );
      connection.send(
        GameSnapshotMessage(_engine.publishedGame.redactedForPlayers()),
      );
    } on Object {
      connection.send(
        const ProtocolErrorMessage(
          code: 'recoveryUnavailable',
          message: 'Identity reassignment could not be saved. Ask the host to retry before continuing.',
        ),
      );
      if (_connections.containsKey(connection.id)) {
        connection.identityRetry = Timer(const Duration(seconds: 2), () {
          if (_connections.containsKey(connection.id) &&
              connection.playerId == id) {
            unawaited(_completeRebind(connection, id, token));
          }
        });
      }
    }
  }

  LobbySnapshotMessage _lobbySnapshot() => LobbySnapshotMessage(
    teams: _engine.publishedGame.teams,
    requiresTeam: _engine.publishedGame.poker != null,
    codeRequired: _engine.access.state.codeHash != null,
    locked: _engine.access.state.locked,
    requireApproval: _engine.access.state.requireApproval,
  );

  bool _checkCode(_Connection connection, String? code) {
    final hash = _engine.access.state.codeHash;
    if (hash == null) return true;
    if (_now() - _codeWindowStart >=
        const Duration(minutes: 1).inMicroseconds) {
      _codeWindowStart = _now();
      _failedCodes = 0;
    }
    // The session-wide budget survives new sockets, including relay sockets.
    if (_failedCodes >= 10 || connection.failedCodes >= 5) {
      _reject(
        connection,
        'codeRateLimited',
        'Too many code attempts. Wait one minute and reconnect.',
      );
      return false;
    }
    if (code == null || code.isEmpty) {
      _reject(
        connection,
        'codeRequired',
        'Enter the join code supplied by the host.',
      );
      return false;
    }
    if (code.length > 64 || SessionAccess.digestCredential(code) != hash) {
      _failedCodes++;
      connection.failedCodes++;
      _reject(
        connection,
        'invalidCode',
        'The join code is missing or incorrect.',
      );
      return false;
    }
    return true;
  }

  void _reject(
    _Connection connection,
    String code,
    String message, {
    bool close = false,
  }) {
    connection.send(ProtocolErrorMessage(code: code, message: message));
    if (close) {
      _onDisconnected(connection);
      unawaited(connection.closeSocket());
    }
  }

  void _accessChanged(SessionAccessState policy) {
    for (final connection in _connections.values.toList()) {
      if (connection.isSpectator &&
          (!policy.allowSpectators ||
              connection.spectatorCodeHash != policy.codeHash)) {
        _reject(
          connection,
          'spectatorAccessChanged',
          'Spectator access changed. Enter the current code to reconnect.',
          close: true,
        );
        continue;
      }
      final pending = connection.pendingJoin;
      if (pending != null) {
        final decision = policy.requests[connection.id]?.decision;
        if (policy.locked || decision == AdmissionDecision.rejected) {
          connection.pendingJoin = null;
          _reject(
            connection,
            policy.locked ? 'lobbyLocked' : 'admissionRejected',
            policy.locked
                ? 'The lobby is locked. Existing players can still reconnect.'
                : 'The host declined your join request.',
            close: true,
          );
        } else if (decision == AdmissionDecision.approved) {
          connection.pendingJoin = null;
          _engine.access.forget(connection.id);
          unawaited(_onFrame(connection, pending.encode(), approved: true));
        }
      } else if (connection.isLobby) {
        connection.send(_lobbySnapshot());
      }
    }
    unawaited(_saveAccess());
  }

  Future<void> _saveAccess() async {
    try {
      await _engine.persistRecovery?.call();
    } on Object {
      _log(
        ServerLogLevel.error,
        'Session access settings could not be saved. Retry recovery storage.',
      );
    }
  }

  void _log(ServerLogLevel level, String message) => _onLog?.call(
    ServerLogEntry(level: level, message: message, atMicros: _now()),
  );
}
