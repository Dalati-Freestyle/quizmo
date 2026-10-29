import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shelf/shelf.dart';

import '../core/engine/quiz_engine_bloc.dart';
import '../core/net/session_uri.dart';
import 'handlers/socket_handlers.dart';
import 'handlers/media_handlers.dart';
import 'server_contract.dart';

/// Publishes a browser-owned engine through a same-origin internet relay.
/// Only SocketHub's redacted player messages leave the host.
final class RelayHost implements EmbeddedQuizServer {
  RelayHost({
    required QuizEngineBloc engine,
    required this.origin,
    this.serverName = 'Quizmo Host',
    WebSocketChannel Function(Uri)? connect,
  }) : _engine = engine,
       _connect = connect ?? WebSocketChannel.connect;

  final WebSocketChannel Function(Uri) _connect;

  final Uri origin;
  final String serverName;
  final QuizEngineBloc _engine;
  final _logs = StreamController<ServerLogEntry>.broadcast();
  final _guests = <String, StreamController<String>>{};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  SocketHub? _hub;
  Timer? _heartbeat;
  ServerEndpoint? _endpoint;

  @override
  bool get isRunning => _endpoint != null;
  @override
  ServerEndpoint? get endpoint => _endpoint;
  @override
  int get connectionCount => _hub?.connectionCount ?? 0;
  @override
  bool get servesWebClient => isRunning;
  @override
  Stream<ServerLogEntry> get logs => _logs.stream;

  void _send(Map<String, Object?> message) =>
      _socket?.sink.add(jsonEncode(message));

  @override
  Future<ServerEndpoint> start({int port = 8080}) async {
    if (isRunning) return _endpoint!;
    if (origin.scheme != 'https' &&
        origin.host != 'localhost' &&
        origin.host != '127.0.0.1') {
      throw StateError(
        'Internet hosting requires HTTPS. Configure TLS for your domain.',
      );
    }
    final ready = Completer<String>();
    try {
      final socket = _connect(
        sessionUri(origin).replace(
          scheme: origin.scheme == 'https' ? 'wss' : 'ws',
          path: '/relay/host',
        ),
      );
      _socket = socket;
      await socket.ready.timeout(const Duration(seconds: 10));
      _hub = SocketHub(engine: _engine, serverName: serverName);
      _subscription = socket.stream.listen(
        (dynamic frame) {
          try {
            final json = jsonDecode(frame as String);
            switch (json) {
              case {'type': 'room', 'room': final String room}:
                if (!ready.isCompleted) ready.complete(room);
              case {'type': 'open', 'id': final String id}:
                final guest = StreamController<String>();
                _guests[id] = guest;
                _hub!.attach(
                  stream: guest.stream,
                  send: (data) =>
                      _send({'type': 'frame', 'id': id, 'data': data}),
                  close: () async {
                    _send({'type': 'close', 'id': id});
                  },
                );
              case {
                'type': 'frame',
                'id': final String id,
                'data': final String data,
              }:
                _guests[id]?.add(data);
              case {'type': 'close', 'id': final String id}:
                _guests.remove(id)?.close();
              case {
                'type': 'mediaRequest',
                'request': final String request,
                'asset': final String asset,
                'method': final String method,
                'access': final String? access,
                'range': final String? range,
              }:
                unawaited(_serveMedia(request, asset, method, access, range));
            }
          } on Object {
            socket.sink.close(3002, 'Invalid relay message');
          }
        },
        onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(StateError('Internet relay unavailable.'));
          }
          _endpoint = null;
          if (!_engine.isClosed) _engine.add(const PauseForRecoveryEvent());
          _heartbeat?.cancel();
          for (final guest in _guests.values) {
            guest.close();
          }
          _guests.clear();
          if (!_logs.isClosed) {
            _logs.add(
              ServerLogEntry(
                level: ServerLogLevel.error,
                message: 'Internet connection lost. Restart hosting and share the new room link.',
                atMicros: DateTime.now().microsecondsSinceEpoch,
              ),
            );
          }
        },
        onError: (Object error) {
          if (!ready.isCompleted) {
            ready.completeError(StateError('Internet relay unavailable.'));
          }
        },
      );
      final room = await ready.future.timeout(const Duration(seconds: 10));
      _endpoint = ServerEndpoint(
        port: origin.port,
        addresses: [origin.host],
        publicUri: sessionUri(origin).replace(path: '/rooms/$room'),
        recoverySessionId: _engine.recoverySessionId,
      );
      _heartbeat = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _send({'type': 'ping'}),
      );
      return _endpoint!;
    } on Object {
      await stop();
      rethrow;
    }
  }

  Future<void> _serveMedia(
    String request,
    String asset,
    String method,
    String? access,
    String? range,
  ) async {
    try {
      final response = serveMedia(
        Request(
          method,
          Uri(
            scheme: 'https',
            host: 'relay.invalid',
            path: '/api/media/$asset',
            queryParameters: {'access': ?access},
          ),
          headers: {'range': ?range},
        ),
        asset,
        _engine,
      );
      final bytes = await response.read().expand((chunk) => chunk).toList();
      _send({
        'type': 'mediaResponse',
        'request': request,
        'status': response.statusCode,
        'headers': response.headers,
        'body': base64Encode(bytes),
      });
    } on Object {
      _send({
        'type': 'mediaResponse',
        'request': request,
        'status': 502,
        'headers': <String, String>{},
        'body': '',
      });
      if (!_logs.isClosed) {
        _logs.add(
          ServerLogEntry(
            level: ServerLogLevel.error,
            message: 'Media transfer failed. The guest can retry the download.',
            atMicros: DateTime.now().microsecondsSinceEpoch,
          ),
        );
      }
    }
  }

  @override
  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _hub?.close();
    _hub = null;
    for (final guest in _guests.values) {
      await guest.close();
    }
    _guests.clear();
    await _socket?.sink.close();
    _socket = null;
    _endpoint = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _logs.close();
  }
}
