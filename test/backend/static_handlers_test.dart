/// Unit tests of the static web-client handler.
///
/// Covers the three behaviours the browser depends on: correct MIME types,
/// the single page application fallback, and path traversal rejection.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/static_handlers.dart';
import 'package:quizmo/backend/web_client_bundle.dart';
import 'package:quizmo/backend/zip_web_client_bundle.dart';
import 'package:shelf/shelf.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

Request _get(String path, {String method = 'GET'}) =>
    Request(method, Uri.parse('http://localhost:8080$path'));

void main() {
  final bundle = InMemoryWebClientBundle({
    'index.html': _bytes('<html>shell</html>'),
    'main.dart.js': _bytes('console.log(1)'),
    'assets/fonts/Icons.otf': _bytes('font-bytes'),
  });
  final handler = createWebClientHandler(bundle);

  group('createWebClientHandler', () {
    test('serves index.html for the site root', () async {
      final response = await handler(_get('/'));

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(await response.readAsString(), '<html>shell</html>');
    });

    test('announces a JavaScript MIME type for the entry script', () async {
      final response = await handler(_get('/main.dart.js'));

      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        'text/javascript; charset=utf-8',
      );
    });

    test('serves nested assets', () async {
      final response = await handler(_get('/assets/fonts/Icons.otf'));

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'font/otf');
      expect(await response.readAsString(), 'font-bytes');
    });

    test('falls back to the shell for extension-less deep links', () async {
      final response = await handler(_get('/join/some-room'));

      expect(response.statusCode, 200);
      expect(await response.readAsString(), '<html>shell</html>');
    });

    test('404s a missing file instead of returning the shell', () async {
      final response = await handler(_get('/canvaskit/canvaskit.wasm'));

      expect(response.statusCode, 404);
    });

    test('never caches the shell but does cache hashed assets', () async {
      final shell = await handler(_get('/index.html'));
      final asset = await handler(_get('/assets/fonts/Icons.otf'));

      expect(shell.headers['cache-control'], contains('no-store'));
      expect(asset.headers['cache-control'], contains('max-age'));
    });

    test('answers HEAD without a body', () async {
      final response = await handler(_get('/index.html', method: 'HEAD'));

      expect(response.statusCode, 200);
      expect(response.headers['content-length'], '18');
      expect(await response.readAsString(), isEmpty);
    });

    test('rejects any method other than GET and HEAD', () async {
      final response = await handler(_get('/index.html', method: 'POST'));

      expect(response.statusCode, 405);
      expect(response.headers['allow'], 'GET, HEAD');
    });

    test('rejects path traversal out of the bundle root', () async {
      final response = await handler(_get('/..%2f..%2fsecret.txt'));

      expect(response.statusCode, 403);
    });
  });

  group('normaliseWebClientPath', () {
    test('strips empty and dot segments', () {
      expect(normaliseWebClientPath('assets/./fonts/Icons.otf'),
          'assets/fonts/Icons.otf');
    });

    test('resolves parent segments that stay inside the root', () {
      expect(normaliseWebClientPath('assets/../index.html'), 'index.html');
    });

    test('returns null when a parent segment escapes the root', () {
      expect(normaliseWebClientPath('../etc/passwd'), isNull);
    });

    test('returns null for encoded separators and dot segments', () {
      expect(normaliseWebClientPath('..%2F..%2Fsecret.txt'), isNull);
      expect(normaliseWebClientPath('%2e%2e/secret.txt'), isNull);
    });

    test('keeps a trailing slash so directories map onto index.html', () {
      expect(normaliseWebClientPath('docs/'), 'docs/');
    });
  });

  group('mimeTypeFor', () {
    test('maps the types a Flutter Web build ships', () {
      expect(mimeTypeFor('index.html'), startsWith('text/html'));
      expect(mimeTypeFor('flutter.js'), startsWith('text/javascript'));
      expect(mimeTypeFor('canvaskit/canvaskit.wasm'), 'application/wasm');
      expect(mimeTypeFor('assets/AssetManifest.bin'),
          'application/octet-stream');
      expect(mimeTypeFor('icons/Icon-192.png'), 'image/png');
    });

    test('degrades gracefully for unknown and missing extensions', () {
      expect(mimeTypeFor('NOTICES'), 'application/octet-stream');
      expect(mimeTypeFor('weird.xyz'), 'application/octet-stream');
    });
  });

  group('ZipWebClientBundle', () {
    Uint8List zipOf(Map<String, String> files) {
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(ArchiveFile.bytes(entry.key, _bytes(entry.value)));
      }
      return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    }

    test('reports the file count and serves entries', () async {
      final zipped = ZipWebClientBundle.fromBytes(
        zipOf({'index.html': 'hi', 'main.dart.js': 'x'}),
      );

      expect(await zipped.prepare(), 2);
      expect(utf8.decode((await zipped.read('index.html'))!), 'hi');
      expect(await zipped.read('missing.html'), isNull);
    });

    test('treats an absent archive as an empty bundle', () async {
      final zipped = ZipWebClientBundle(
        loadArchive: () async => Uint8List(0),
      );

      expect(await zipped.prepare(), 0);
      expect(await zipped.read('index.html'), isNull);
    });

    test('decodes only once across repeated reads', () async {
      var loads = 0;
      final zipped = ZipWebClientBundle(
        loadArchive: () async {
          loads++;
          return zipOf({'index.html': 'hi'});
        },
      );

      await zipped.read('index.html');
      await zipped.read('index.html');
      await zipped.prepare();

      expect(loads, 1);
    });
  });
}

