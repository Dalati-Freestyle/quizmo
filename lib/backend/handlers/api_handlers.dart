/// REST handlers of the embedded host.
///
/// The surface is deliberately tiny: everything that changes during a round
/// travels over the web socket, the REST API only bootstraps a client.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../../core/sync/clock.dart';
import 'media_handlers.dart';

/// Builds the `/api` router for [engine].
///
/// [serverName] is echoed by `/api/health` so a client can show which device it
/// is about to join.
Router buildApiRouter({
  required QuizEngineBloc engine,
  required String serverName,
  NowMicros now = systemNowMicros,
}) {
  final router = Router();
  router.all(
    '/api/media/<id>',
    (Request request, String id) => serveMedia(request, id, engine),
  );

  /// Liveness probe and server identification.
  router.get('/api/health', (Request request) {
    return _json({
      'status': 'ok',
      'serverName': serverName,
      'hostTimeMicros': now(),
      'players': engine.state.game.connectedPlayers.length,
    });
  });

  /// Clock synchronisation endpoint.
  ///
  /// The client sends `t0` on its own clock and receives it back together with
  /// the host clock `t1`. Combined with the local arrival time `t2` this yields
  /// round trip time and offset (see `ClockSyncEstimator`).
  ///
  /// The host timestamp is read **as late as possible** so that JSON decoding
  /// of the request does not leak into the measured offset.
  router.post('/api/sync-time', (Request request) async {
    final body = await request.readAsString();
    final int clientSentAtMicros;
    try {
      final json = jsonDecode(body) as JsonMap;
      clientSentAtMicros = json.readInt('clientSentAtMicros');
    } on Object catch (error) {
      return _json({'error': 'badRequest', 'message': '$error'}, status: 400);
    }
    return _json({
      'clientSentAtMicros': clientSentAtMicros,
      'hostTimeMicros': now(),
    });
  });

  /// Snapshot of the redacted session state, useful for polling fallbacks.
  router.get('/api/state', (Request request) {
    return _json(engine.publishedGame.redactedForPlayers().toJson());
  });

  return router;
}

Response _json(JsonMap payload, {int status = 200}) => Response(
  status,
  body: jsonEncode(payload),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
