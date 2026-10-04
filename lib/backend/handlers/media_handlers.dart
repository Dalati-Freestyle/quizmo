import 'package:shelf/shelf.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';

/// Serves only attachments currently visible to guests. Uploads happen locally
/// through the host editor, never through an unauthenticated LAN endpoint.
Response serveMedia(Request request, String id, QuizEngineBloc engine) {
  if (request.method != 'GET' && request.method != 'HEAD') return Response(405);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    return Response.notFound('Unknown asset');
  }
  final round = engine.state.game.round;
  final question = round.question;
  if (question == null) return Response.notFound('Unknown asset');
  final media = [
    ...question.media,
    if (round.status == RoundStatus.revealed) ...question.solutionMedia,
  ];
  final asset = media
      .map((m) => m.asset)
      .whereType<MediaAsset>()
      .where((a) => a.id == id)
      .firstOrNull;
  final bytes = asset?.bytes;
  if (asset == null || bytes == null) return Response.notFound('Unknown asset');
  final headers = <String, String>{
    'content-type': asset.mimeType,
    'x-content-type-options': 'nosniff',
    'content-security-policy': "default-src 'none'; sandbox",
    'cache-control': 'no-store',
    'accept-ranges': 'bytes',
    'content-length': '${bytes.length}',
  };
  // HEAD ignores Range, matching GET metadata without allocating a body.
  if (request.method == 'HEAD') return Response.ok(null, headers: headers);
  final range = request.headers['range'];
  if (range == null) return Response.ok(bytes, headers: headers);
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
  Response invalid() => Response(
    416,
    headers: {
      ...headers,
      'content-range': 'bytes */${bytes.length}',
      'content-length': '0',
    },
  );
  if (match == null || match[1]!.isEmpty && match[2]!.isEmpty) return invalid();
  final int start;
  final int end;
  if (match[1]!.isEmpty) {
    final suffix = int.tryParse(match[2]!);
    if (suffix == null || suffix <= 0) return invalid();
    start = (bytes.length - suffix).clamp(0, bytes.length);
    end = bytes.length - 1;
  } else {
    final parsedStart = int.tryParse(match[1]!);
    final parsedEnd = match[2]!.isEmpty
        ? bytes.length - 1
        : int.tryParse(match[2]!);
    if (parsedStart == null || parsedEnd == null) return invalid();
    start = parsedStart;
    end = parsedEnd.clamp(0, bytes.length - 1);
  }
  if (start >= bytes.length || end < start) return invalid();
  return Response(
    206,
    body: bytes.sublist(start, end + 1),
    headers: {
      ...headers,
      'content-range': 'bytes $start-$end/${bytes.length}',
      'content-length': '${end - start + 1}',
    },
  );
}
