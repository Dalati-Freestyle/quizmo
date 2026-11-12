import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizmo/core/models/media_attachment.dart';
import 'package:quizmo/core/net/media_cache.dart';

void main() {
  final bytes = Uint8List.fromList(utf8.encode('<svg>${' ' * 4096}</svg>'));
  final embedded = MediaAsset.upload(bytes, 'svg');
  final reference = MediaAsset(id: embedded.id, mimeType: embedded.mimeType);
  final base = Uri.parse(
    'https://host/rooms/first?access=private&session=game',
  );

  test('LAN and internet media URLs retain only the room capability', () {
    expect(
      sessionMediaUri(base, reference).path,
      '/rooms/first/api/media/${reference.id}',
    );
    expect(sessionMediaUri(base, reference).queryParameters, {
      'access': 'private',
    });
    expect(
      sessionMediaUri(Uri.parse('http://host:8080?access=lan'), reference).path,
      reference.route,
    );
  });

  test(
    'concurrent loads and 100 repeated references transfer bytes once',
    () async {
      var requests = 0;
      var transferred = 0;
      final cache = SessionMediaCache(
        baseUri: base,
        createClient: () => MockClient((request) async {
          expect(request.url.path, '/rooms/first${reference.route}');
          expect(request.url.queryParameters['access'], 'private');
          requests++;
          transferred += bytes.length;
          await Future<void>.delayed(Duration.zero);
          return http.Response.bytes(bytes, 200);
        }),
      );
      addTearDown(cache.dispose);
      final first = cache.load(reference);
      expect(identical(first, cache.load(reference)), isTrue);
      expect((await first).data, embedded.data);
      for (var i = 0; i < 100; i++) {
        expect((await cache.load(reference)).id, embedded.id);
      }
      expect(requests, 1);
      expect(transferred, bytes.length);
      expect(transferred, lessThan(bytes.length * 101 ~/ 100));
    },
  );

  test('errors are not cached and retries can succeed', () async {
    var attempts = 0;
    final cache = SessionMediaCache(
      baseUri: base,
      createClient: () => MockClient(
        (_) async => ++attempts == 1
            ? http.Response('Admission required', 403)
            : http.Response.bytes(bytes, 200),
      ),
    );
    addTearDown(cache.dispose);
    await expectLater(cache.load(reference), throwsStateError);
    expect((await cache.load(reference)).data, embedded.data);
    expect(attempts, 2);
  });

  test(
    'damaged, oversized and truncated downloads fail without caching',
    () async {
      for (final response in [
        http.Response.bytes([1, 2, 3], 200),
        http.Response.bytes(
          [],
          200,
          headers: {'content-length': '${maxMediaBytes + 1}'},
        ),
      ]) {
        var attempts = 0;
        final cache = SessionMediaCache(
          baseUri: base,
          createClient: () => MockClient((_) async {
            attempts++;
            return response;
          }),
        );
        addTearDown(cache.dispose);
        await expectLater(cache.load(reference), throwsFormatException);
        await expectLater(cache.load(reference), throwsFormatException);
        expect(attempts, 2);
      }
      final truncated = SessionMediaCache(
        baseUri: base,
        createClient: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length + 1,
          ),
        ),
      );
      addTearDown(truncated.dispose);
      await expectLater(truncated.load(reference), throwsFormatException);
    },
  );

  test(
    'progress reports received bytes and a stalled download times out',
    () async {
      final chunks = StreamController<List<int>>();
      final cache = SessionMediaCache(
        baseUri: base,
        timeout: const Duration(milliseconds: 100),
        createClient: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            chunks.stream,
            200,
            contentLength: bytes.length,
          ),
        ),
      );
      addTearDown(cache.dispose);
      final update = cache.updates.first;
      final load = cache.load(reference);
      final failure = expectLater(load, throwsA(isA<TimeoutException>()));
      chunks.add(bytes.sublist(0, 100));
      await update;
      expect(cache.progress(reference.id)!.received, 100);
      expect(cache.progress(reference.id)!.fraction, 100 / bytes.length);
      await failure;
      await chunks.close();
    },
  );

  test('late bytes after timeout cannot enter the cache', () async {
    final chunks = StreamController<List<int>>();
    var requests = 0;
    final cache = SessionMediaCache(
      baseUri: base,
      timeout: const Duration(milliseconds: 20),
      createClient: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          ++requests == 1 ? chunks.stream : Stream.value(bytes),
          200,
        ),
      ),
    );
    addTearDown(cache.dispose);
    await expectLater(cache.load(reference), throwsA(isA<TimeoutException>()));
    chunks.add(bytes);
    await chunks.close();
    expect((await cache.load(reference)).data, embedded.data);
    expect(requests, 2);
  });

  test('at most four different files download concurrently', () async {
    var active = 0;
    var peak = 0;
    final assets = [
      for (var i = 0; i < 12; i++)
        MediaAsset.upload(
          Uint8List.fromList(utf8.encode('<svg>$i</svg>')),
          'svg',
        ),
    ];
    final cache = SessionMediaCache(
      baseUri: base,
      createClient: () => MockClient((request) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return http.Response.bytes(
          assets.firstWhere((a) => request.url.path.endsWith(a.id)).bytes!,
          200,
        );
      }),
    );
    addTearDown(cache.dispose);
    await Future.wait([
      for (final asset in assets)
        cache.load(MediaAsset(id: asset.id, mimeType: asset.mimeType)),
    ]);
    expect(peak, 4);
    expect(active, 0);
  });

  test(
    'LRU eviction is bounded and separate rooms never share cached bytes',
    () async {
      final otherBytes = Uint8List.fromList(utf8.encode('<svg>other</svg>'));
      final other = MediaAsset.upload(otherBytes, 'svg');
      final otherReference = MediaAsset(id: other.id, mimeType: other.mimeType);
      var requests = 0;
      http.Client createClient() => MockClient((request) async {
        requests++;
        return http.Response.bytes(
          request.url.path.endsWith(other.id) ? otherBytes : bytes,
          200,
        );
      });
      final cache = SessionMediaCache(
        baseUri: base,
        maxBytes: embedded.data!.length,
        createClient: createClient,
      );
      final secondRoom = SessionMediaCache(
        baseUri: Uri.parse('https://host/rooms/second?access=different'),
        createClient: createClient,
      );
      addTearDown(cache.dispose);
      addTearDown(secondRoom.dispose);
      await cache.load(reference);
      await cache.load(otherReference);
      await cache.load(reference);
      expect(requests, 3);
      await secondRoom.load(reference);
      expect(requests, 4);
      cache.dispose();
      await expectLater(cache.load(reference), throwsStateError);
    },
  );
}
