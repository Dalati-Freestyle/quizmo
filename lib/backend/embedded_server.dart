/// The embedded HTTP and web socket host.
///
/// This file is `dart:io` only. It is never reachable from a Flutter Web build
/// because the presentation layer obtains its instance through
/// `server_launcher.dart`, which swaps in a stub for the browser.
///
/// ## Routes
///
/// | Method   | Path             | Purpose                                   |
/// | -------- | ---------------- | ----------------------------------------- |
/// | GET      | `/api/health`    | Liveness probe and server identification  |
/// | POST     | `/api/sync-time` | NTP style clock handshake                 |
/// | GET      | `/api/state`     | Redacted snapshot (polling fallback)      |
/// | GET      | `/ws`            | Web socket upgrade for live play          |
/// | GET/HEAD | `/<anything>`    | The bundled Flutter Web player            |
///
/// The catch-all is registered last, so the API always wins. When no web client
/// bundle is supplied — or the bundle turns out to be empty — the fallback
/// serves a small placeholder page that points at the API instead.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../core/engine/quiz_engine_bloc.dart';
import '../core/sync/clock.dart';
import 'handlers/api_handlers.dart';
import 'handlers/cors_middleware.dart';
import 'handlers/socket_handlers.dart';
import 'handlers/static_handlers.dart';
import 'lan_addresses.dart';
import 'server_contract.dart';
import 'web_client_bundle.dart';

/// Default port of the embedded host.
const int kDefaultServerPort = 8080;

/// A quiz host that runs inside the Flutter app process.
class EmbeddedServer implements EmbeddedQuizServer {
  /// Creates a server that serves the session owned by [engine].
  ///
  /// [webClient] supplies the static Flutter Web player that guests load in
  /// their browser. Leaving it `null` keeps the host API-only.
  EmbeddedServer({
    required QuizEngineBloc engine,
    this.serverName = 'Quizmo Host',
    NowMicros now = systemNowMicros,
    WebClientBundle? webClient,
  }) : _engine = engine,
       _now = now,
       _webClient = webClient;

  /// Friendly name announced to clients.
  final String serverName;

  final QuizEngineBloc _engine;
  final NowMicros _now;
  final WebClientBundle? _webClient;
  final StreamController<ServerLogEntry> _logs =
      StreamController<ServerLogEntry>.broadcast();

  HttpServer? _httpServer;
  SocketHub? _hub;
  ServerEndpoint? _endpoint;
  bool _servesWebClient = false;

  @override
  bool get isRunning => _httpServer != null;

  @override
  ServerEndpoint? get endpoint => _endpoint;

  @override
  int get connectionCount => _hub?.connectionCount ?? 0;

  @override
  Stream<ServerLogEntry> get logs => _logs.stream;

  /// Whether a non-empty web player bundle is being served at `/`.
  @override
  bool get servesWebClient => _servesWebClient;

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

    // Registered last so that `/api/**` and `/ws` keep priority over the
    // single page application fallback inside the static handler.
    router.all('/<path|.*>', await _buildWebClientHandler());

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
    if (_servesWebClient) {
      _log(
        ServerLogLevel.info,
        'Players can open ${endpoint.lanUri} directly in a browser.',
      );
    }
    return endpoint;
  }

  @override
  Future<void> stop() async {
    await _hub?.close();
    _hub = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    _endpoint = null;
    _servesWebClient = false;
    _log(ServerLogLevel.info, 'Server stopped.');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _logs.close();
  }

  /// Resolves the handler for the `/` catch-all route.
  ///
  /// The bundle is prepared eagerly so that a broken or missing archive is
  /// reported once at startup rather than on every request.
  Future<Handler> _buildWebClientHandler() async {
    final bundle = _webClient;
    if (bundle == null) {
      _log(
        ServerLogLevel.info,
        'No web client bundle configured — serving the API only.',
      );
      return _placeholderHandler;
    }

    int fileCount;
    try {
      fileCount = await bundle.prepare();
    } on Object catch (error) {
      _log(
        ServerLogLevel.error,
        'Web client bundle (${bundle.description}) failed to load: $error',
      );
      return _placeholderHandler;
    }

    if (fileCount == 0) {
      _log(
        ServerLogLevel.warning,
        'Web client bundle (${bundle.description}) is empty. Run '
        '`dart run tool/bundle_web_client.dart` to pack the Flutter Web build.',
      );
      return _placeholderHandler;
    }

    _servesWebClient = true;
    _log(
      ServerLogLevel.info,
      'Serving $fileCount web client files from ${bundle.description}.',
    );
    return createWebClientHandler(bundle);
  }

  /// Answers the `/` catch-all when no web player is available.
  Response _placeholderHandler(Request request) {
    if (request.url.path.isNotEmpty) {
      return Response.notFound('Not found: /${request.url.path}');
    }
    return Response.ok(
      '<!DOCTYPE html>'
      '<html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>${_escape(serverName)}</title></head>'
      '<body style="font-family:system-ui;margin:0;display:grid;'
      'place-items:center;min-height:100vh;background:#111;color:#eee">'
      '<main style="max-width:32rem;padding:2rem;text-align:center">'
      '<h1>${_escape(serverName)}</h1>'
      '<p>This host is running, but the web player has not been bundled '
      'into the app. Join with the Quizmo app, or rebuild the host after '
      'running <code>dart run tool/bundle_web_client.dart</code>.</p>'
      '<p><a style="color:#8ea1ff" href="/api/health">/api/health</a></p>'
      '</main></body></html>',
      headers: const {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }

  static String _escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  /// Collects every IPv4 address the host is reachable at, best candidate
  /// first.
  ///
  /// Ordering matters: a phone on Wi-Fi *and* mobile data reports several
  /// addresses, and only the Wi-Fi one is routable for a guest. Handing out
  /// the mobile `192.0.0.x` translation address instead produces a connection
  /// timeout that looks exactly like a firewall problem. See
  /// `lan_addresses.dart` for the ranking.
  ///
  /// Enumeration can be denied by the platform (for example without the local
  /// network entitlement on iOS), in which case loopback is still returned so
  /// an on-device demo keeps working.
  Future<List<String>> _localAddresses() async {
    final candidates = <LanAddressCandidate>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          candidates.add(
            LanAddressCandidate(
              address: address.address,
              interfaceName: interface.name,
            ),
          );
        }
      }
    } on Object catch (error) {
      _log(ServerLogLevel.warning, 'Interface enumeration failed: $error');
    }

    final addresses = sortLanAddresses(candidates);
    if (candidates.length > 1) {
      _log(
        ServerLogLevel.info,
        'Reachable at ${addresses.join(', ')} — '
        'announcing ${addresses.first}.',
      );
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
