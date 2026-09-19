/// Static file handler that serves the bundled Flutter Web player.
///
/// The Flutter Web build is a single page application: deep links such as
/// `/join/abc` do not exist on disk and must fall back to `index.html` so the
/// Dart router can take over. Requests that clearly address a file (they carry
/// an extension) never fall back — a missing `main.dart.js` has to surface as a
/// `404` instead of silently returning HTML.
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../web_client_bundle.dart';

/// Entry document of the Flutter Web build.
const String kWebClientIndex = 'index.html';

/// Maps a file extension (without the dot) to the MIME type announced to the
/// browser. Everything unknown degrades to `application/octet-stream`.
const Map<String, String> _mimeTypes = {
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'json': 'application/json; charset=utf-8',
  'map': 'application/json; charset=utf-8',
  'wasm': 'application/wasm',
  'txt': 'text/plain; charset=utf-8',
  'md': 'text/plain; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'ico': 'image/x-icon',
  'bin': 'application/octet-stream',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'webmanifest': 'application/manifest+json',
};

/// Files that must never be cached, otherwise a rebuilt bundle keeps serving
/// the previous session's JavaScript out of the browser cache.
const Set<String> _noCacheFiles = {
  kWebClientIndex,
  'flutter_bootstrap.js',
  'flutter_service_worker.js',
  'version.json',
};

/// Returns the MIME type announced for [path].
String mimeTypeFor(String path) {
  final extension = p.url.extension(path);
  if (extension.isEmpty) return 'application/octet-stream';
  return _mimeTypes[extension.substring(1).toLowerCase()] ??
      'application/octet-stream';
}

/// Builds a handler that serves [bundle] as the site root.
///
/// The handler answers `GET` and `HEAD`; every other method yields `405` so
/// that a mistyped API call is not mistaken for a missing page.
Handler createWebClientHandler(WebClientBundle bundle) {
  return (Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, headers: const {'allow': 'GET, HEAD'});
    }

    final requested = normaliseWebClientPath(request.url.path);
    if (requested == null) {
      // The path escaped the bundle root via `..` segments.
      return Response.forbidden('Invalid path.');
    }

    var path = requested;
    var bytes = await bundle.read(path);

    // Directory style requests (`/`, `/rules/`) map onto their index document.
    if (bytes == null && (path.isEmpty || path.endsWith('/'))) {
      path = p.url.join(path, kWebClientIndex);
      bytes = await bundle.read(path);
    }

    // Single page application fallback: extension-less deep links are routes,
    // not files, so hand the shell to the client side router.
    if (bytes == null && p.url.extension(path).isEmpty) {
      path = kWebClientIndex;
      bytes = await bundle.read(path);
    }

    if (bytes == null) {
      return Response.notFound(
        'Not found: /${requested.isEmpty ? '' : requested}',
      );
    }

    return _fileResponse(path: path, bytes: bytes, isHead: request.method == 'HEAD');
  };
}

/// Normalises the URL path of a request into a bundle relative file path.
///
/// Expects the already percent-decoded path of `Request.url`, so it must not
/// decode a second time — `%252e%252e` would otherwise collapse into `..`.
/// What `Uri` leaves encoded are exactly the reserved characters that could
/// smuggle a separator or a dot segment past this check (`%2f`, `%2e`), and a
/// Flutter Web build never needs a `%` in a file name. Rejecting them outright
/// is therefore both safe and lossless.
///
/// Returns `null` when the path tries to escape the bundle root.
String? normaliseWebClientPath(String urlPath) {
  final hadTrailingSlash = urlPath.endsWith('/');
  final segments = <String>[];
  for (final segment in urlPath.split('/')) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (segments.isEmpty) return null;
        segments.removeLast();
      default:
        if (segment.contains('%')) return null;
        segments.add(segment);
    }
  }
  final joined = segments.join('/');
  if (joined.isEmpty) return '';
  return hadTrailingSlash ? '$joined/' : joined;
}

Response _fileResponse({
  required String path,
  required Uint8List bytes,
  required bool isHead,
}) {
  final headers = <String, String>{
    'content-type': mimeTypeFor(path),
    'content-length': '${bytes.length}',
    // Hashed Flutter assets are safe to cache; the shell and the bootstrap
    // scripts are not, because they pin the version of everything else.
    'cache-control': _noCacheFiles.contains(path)
        ? 'no-cache, no-store, must-revalidate'
        : 'public, max-age=3600',
  };
  return Response.ok(isHead ? null : bytes, headers: headers);
}

