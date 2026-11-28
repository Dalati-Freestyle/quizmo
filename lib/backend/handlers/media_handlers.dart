import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';

bool mayReadSession(Request request, QuizEngineBloc engine) {
  final authorization = request.headers['authorization'];
  final token = authorization != null && authorization.startsWith('Bearer ')
      ? authorization.substring(7)
      : request.url.queryParameters['access'];
  return engine.access.mayRead(token);
}

/// Serves only attachments currently visible to guests. Uploads happen locally
/// through the host editor, never through an unauthenticated LAN endpoint.
///
/// With [maxBodyBytes] (internet relay) no response carries more than that:
/// ranges are shortened and a plain GET of a larger asset is answered like
/// `Range: bytes=0-`, so the client continues with further ranges.
Response serveMedia(
  Request request,
  String id,
  QuizEngineBloc engine, {
  int? maxBodyBytes,
}) {
  if (!mayReadSession(request, engine)) {
    return Response.forbidden('Admission required');
  }
  if (request.method != 'GET' && request.method != 'HEAD') return Response(405);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    return Response.notFound('Unknown asset');
  }
  // A preload handle: any upload of the quiz, but encrypted; its key only
  // travels once the medium is visible.
  final preload = engine.mediaPreload.byHandle(id);
  final asset =
      preload?.asset ??
      visibleGuestMedia(engine.publishedGame)
          .map((m) => m.asset)
          .whereType<MediaAsset>()
          .where((a) => a.id == id)
          .firstOrNull;
  final bytes = asset?.bytes;
  if (asset == null || bytes == null) return Response.notFound('Unknown asset');
  Uint8List body(int start, int end) => preload == null
      ? bytes.sublist(start, end + 1)
      : preload.encryptedRange(start, end);
  final headers = <String, String>{
    // Nothing about an encrypted file tells what it contains.
    'content-type': preload == null
        ? asset.mimeType
        : 'application/octet-stream',
    'x-content-type-options': 'nosniff',
    'content-security-policy': "default-src 'none'; sandbox",
    'cache-control': 'no-store',
    'accept-ranges': 'bytes',
    'content-length': '${bytes.length}',
  };
  // HEAD ignores Range, matching GET metadata without allocating a body.
  if (request.method == 'HEAD') return Response.ok(null, headers: headers);
  final range =
      request.headers['range'] ??
      (maxBodyBytes != null && bytes.length > maxBodyBytes ? 'bytes=0-' : null);
  if (range == null) {
    return Response.ok(
      bytes.isEmpty ? bytes : body(0, bytes.length - 1),
      headers: headers,
    );
  }
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
  int end;
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
  if (maxBodyBytes != null && end - start + 1 > maxBodyBytes) {
    end = start + maxBodyBytes - 1;
  }
  if (start >= bytes.length || end < start) return invalid();
  return Response(
    206,
    body: body(start, end),
    headers: {
      ...headers,
      'content-range': 'bytes $start-$end/${bytes.length}',
      'content-length': '${end - start + 1}',
    },
  );
}
