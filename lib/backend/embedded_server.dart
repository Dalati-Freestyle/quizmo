/// The embedded HTTP and web socket host.
///
/// This file is `dart:io` only. It is never reachable from a Flutter Web build
/// because the presentation layer obtains its instance through
/// `server_launcher.dart`, which swaps in a stub for the browser.
///
/// ## Routes
///
/// | Method | Path             | Purpose                                   |
/// | ------ | ---------------- | ----------------------------------------- |
/// | GET    | `/api/health`    | Liveness probe and server identification  |
/// | POST   | `/api/sync-time` | NTP style clock handshake                 |
/// | GET    | `/api/state`     | Redacted snapshot (polling fallback)      |
/// | GET    | `/ws`            | Web socket upgrade for live play          |
library;

import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../core/engine/quiz_engine_bloc.dart';
import '../core/sync/clock.dart';
import 'handlers/api_handlers.dart';
import 'handlers/cors_middleware.dart';
import 'handlers/socket_handlers.dart';
import 'server_contract.dart';

/// Default port of the embedded host.
const int kDefaultServerPort = 8080;

/// A quiz host that runs inside the Flutter app process.
class EmbeddedServer implements EmbeddedQuizServer {
  /// Creates a server that serves the session owned by [engine].
  EmbeddedServer({
    required QuizEngineBloc engine,
    this.serverName = 'Quizmo Host',
    NowMicros now = systemNowMicros,
  }) : _engine = engine,
       _now = now;

  /// Friendly name announced to clients.
  final String serverName;

  final QuizEngineBloc _engine;
  final NowMicros _now;
  final StreamController<ServerLogEntry> _logs =
      StreamController<ServerLogEntry>.broadcast();

  HttpServer? _httpServer;
  SocketHub? _hub;
  ServerEndpoint? _endpoint;

  @override
  bool get isRunning => _httpServer != null;

  @override
  ServerEndpoint? get endpoint => _endpoint;

  @override
  int get connectionCount => _hub?.connectionCount ?? 0;

  @override
  Stream<ServerLogEntry> get logs => _logs.stream;

  @override
  Future<ServerEndpoint> start({int port = kDefaultServerPort}) async {
    if (isRunning) return _endpoint!;

    final hub = SocketHub(
      engine: _engine,
      serverName: serverName,
      now: _now,
      onLog: _emitLog,
    );
    _hub = hub;

    final router = buildApiRouter(
      engine: _engine,
      serverName: serverName,
      now: _now,
    )..get('/ws', hub.handler);

    final handler = const Pipeline()
        .addMiddleware(corsMiddleware())
        .addHandler(router.call);

    try {
      _httpServer = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } on Object catch (error) {
      await hub.close();
      _hub = null;
      _log(ServerLogLevel.error, 'Could not bind to port $port: $error');
      rethrow;
    }

    final endpoint = ServerEndpoint(
      port: _httpServer!.port,
      addresses: await _localAddresses(),
    );
    _endpoint = endpoint;
    _log(
      ServerLogLevel.info,
      'Listening on ${endpoint.lanUri} (and ${endpoint.loopbackUri}).',
    );
    return endpoint;
  }

  @override
  Future<void> stop() async {
    await _hub?.close();
    _hub = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    _endpoint = null;
    _log(ServerLogLevel.info, 'Server stopped.');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _logs.close();
  }

  /// Collects every IPv4 address the host is reachable at, loopback first.
  ///
  /// Enumeration can be denied by the platform (for example without the local
  /// network entitlement on iOS), in which case loopback is still returned so
  /// an on-device demo keeps working.
  Future<List<String>> _localAddresses() async {
    final addresses = <String>['127.0.0.1'];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          addresses.add(address.address);
        }
      }
    } on Object catch (error) {
      _log(ServerLogLevel.warning, 'Interface enumeration failed: $error');
    }
    return addresses;
  }

  void _log(ServerLogLevel level, String message) => _emitLog(
    ServerLogEntry(level: level, message: message, atMicros: _now()),
  );

  void _emitLog(ServerLogEntry entry) {
    if (!_logs.isClosed) _logs.add(entry);
  }
}

