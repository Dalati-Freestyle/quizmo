/// Web socket hub of the embedded host.
///
/// Owns the open connections, translates inbound [ClientMessage]s into
/// [QuizEngineEvent]s and pushes every engine transition back to the clients as
/// a redacted [GameSnapshotMessage].
library;

import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../../core/protocol/messages.dart';
import '../../core/sync/clock.dart';
import '../server_contract.dart';

/// One open web socket, possibly not joined yet.
final class _Connection {
  _Connection({required this.id, required this.channel});

  final String id;
  final WebSocketChannel channel;
  StreamSubscription<dynamic>? subscription;

  /// Authoritative player id; `null` until the join request was accepted.
  String? playerId;

  /// Whether this socket only watches (TV screen); it never owns a player.
  bool isSpectator = false;

  void send(ServerMessage message) {
    try {
      channel.sink.add(message.encode());
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
    _engineSubscription = _engine.stream.listen(_broadcastState);
  }

  /// Friendly name announced to every client.
  final String serverName;

  final QuizEngineBloc _engine;
  final NowMicros _now;
  final void Function(ServerLogEntry entry)? _onLog;
  final Map<String, _Connection> _connections = <String, _Connection>{};

  StreamSubscription<QuizEngineState>? _engineSubscription;
  var _nextConnectionId = 0;

  /// Number of open sockets.
  int get connectionCount => _connections.length;

  /// The shelf handler that performs the web socket upgrade.
  Handler get handler => webSocketHandler(
    (WebSocketChannel channel, String? protocol) => _onConnected(channel),
  );

  /// Closes every socket and stops listening to the engine.
  Future<void> close() async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    final connections = _connections.values.toList(growable: false);
    _connections.clear();
    for (final connection in connections) {
      await connection.subscription?.cancel();
      await connection.channel.sink.close();
    }
  }

  // --------------------------------------------------------------- internals ---

  void _onConnected(WebSocketChannel channel) {
    final connection = _Connection(
      id: 'conn-${_nextConnectionId++}',
      channel: channel,
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

    connection.subscription = channel.stream.listen(
      (Object? frame) => _onFrame(connection, frame),
      onDone: () => _onDisconnected(connection),
      onError: (Object error) {
        _log(ServerLogLevel.warning, 'Socket ${connection.id}: $error');
        _onDisconnected(connection);
      },
      cancelOnError: true,
    );
  }

  void _onFrame(_Connection connection, Object? frame) {
    if (frame is! String) return;

    final ClientMessage message;
    try {
      message = ClientMessage.decode(frame);
    } on Object catch (error) {
      connection.send(
        ProtocolErrorMessage(code: 'badRequest', message: '$error'),
      );
      return;
    }

    switch (message) {
      case JoinRequest(
        :final name,
        :final teamId,
        :final resumePlayerId,
        :final clockOffsetMicros,
        :final roundTripMicros,
      ):
        final playerId = resumePlayerId ?? newId('player');
        connection.playerId = playerId;
        _engine.add(
          PlayerJoinedEvent(
            Player(
              id: playerId,
              name: name,
              teamId: teamId,
              clockOffsetMicros: clockOffsetMicros,
              roundTripMicros: roundTripMicros,
            ),
          ),
        );
        connection.send(
          JoinAcceptedMessage(playerId: playerId, hostTimeMicros: _now()),
        );
        connection.send(
          GameSnapshotMessage(_engine.state.game.redactedForPlayers()),
        );
        _log(ServerLogLevel.info, '$name joined as $playerId.');

      case WatchRequest():
        // Spectators are deliberately anonymous: no roster entry, no clock
        // sync and no way to submit, so a TV can never influence a round.
        connection.isSpectator = true;
        connection.send(const WatchAcceptedMessage());
        connection.send(
          GameSnapshotMessage(_engine.state.game.redactedForPlayers()),
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
    }
  }

  void _onDisconnected(_Connection connection) {
    if (_connections.remove(connection.id) == null) return;
    connection.subscription?.cancel();
    final playerId = connection.playerId;
    if (playerId != null) _engine.add(PlayerLeftEvent(playerId));
    _log(ServerLogLevel.info, 'Socket ${connection.id} disconnected.');
  }

  void _broadcastState(QuizEngineState state) {
    if (_connections.isEmpty) return;
    final message = GameSnapshotMessage(state.game.redactedForPlayers());
    for (final connection in _connections.values.toList(growable: false)) {
      connection.send(message);
    }
  }

  void _log(ServerLogLevel level, String message) => _onLog?.call(
    ServerLogEntry(level: level, message: message, atMicros: _now()),
  );
}
