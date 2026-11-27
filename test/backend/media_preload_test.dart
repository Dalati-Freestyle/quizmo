import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/backend/handlers/media_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/chacha20.dart';
import 'package:quizmo/core/net/media_cache.dart';
import 'package:quizmo/core/net/media_preloader.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:shelf/shelf.dart';

MediaAsset svg(String color) => MediaAsset.upload(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" '
      'fill="$color"/></svg>',
    ),
  ),
  'svg',
);

final questionPicture = svg('red');
final solutionPicture = svg('blue');
final hintPicture = svg('green');

final question = TrueFalseQuestion(
  id: 'q',
  prompt: 'Rot?',
  correctAnswer: true,
  media: [ImageAttachment(asset: questionPicture)],
  solutionMedia: [ImageAttachment(asset: solutionPicture)],
  hints: [
    QuestionHint(media: [ImageAttachment(asset: hintPicture)]),
  ],
);

QuizEngineBloc engineWith() => QuizEngineBloc(
  questionBank: [
    question,
    const TrueFalseQuestion(
      id: 'yt',
      prompt: 'Video?',
      media: [VideoAttachment(youtubeId: 'dQw4w9WgXcQ')],
    ),
  ],
);

Response get(QuizEngineBloc engine, String id, {String? range}) => serveMedia(
  Request(
    'GET',
    Uri.parse('http://localhost/api/media/$id'),
    headers: {'range': ?range},
  ),
  id,
  engine,
);

Future<void> send(QuizEngineBloc engine, QuizEngineEvent event) async {
  engine.add(event);
  await pumpEventQueue();
}

void main() {
  group('host', () {
    test('offers every upload under a random handle, online media apart', () {
      final engine = engineWith();
      addTearDown(engine.close);
      final manifest = engine.mediaPreload.manifest;
      expect(manifest.items, hasLength(3));
      expect(manifest.onlineCount, 1);
      final handles = {for (final item in manifest.items) item.handle};
      expect(handles, hasLength(3));
      for (final asset in [questionPicture, solutionPicture, hintPicture]) {
        expect(handles, isNot(contains(asset.id)));
      }
      expect(jsonEncode(manifest.toJson()), isNot(contains('svg')));
    });

    test(
      'serves only encrypted bytes under a handle, also in ranges',
      () async {
        final engine = engineWith();
        addTearDown(engine.close);
        final item = engine.mediaPreload.manifest.items.first;
        final entry = engine.mediaPreload.byHandle(item.handle)!;
        final response = get(engine, item.handle);
        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'application/octet-stream');
        final cipher = Uint8List.fromList(
          await response.read().expand((c) => c).toList(),
        );
        expect(cipher, isNot(entry.asset.bytes));
        expect(chacha20(entry.key, Uint8List(12), cipher), entry.asset.bytes);
        final part = get(engine, item.handle, range: 'bytes=5-20');
        expect(part.statusCode, 206);
        expect(
          await part.read().expand((c) => c).toList(),
          cipher.sublist(5, 21),
        );
        // Plain media stay hidden until they may be seen.
        expect(get(engine, entry.asset.id).statusCode, 404);
      },
    );

    test('keys travel only for media guests may see', () async {
      final engine = engineWith();
      addTearDown(engine.close);
      Set<String> keyed() => {
        for (final key in engine.mediaPreload.keysFor(engine.publishedGame))
          key.assetId,
      };
      expect(keyed(), isEmpty);
      await send(engine, const StartRoundEvent('q'));
      expect(keyed(), {questionPicture.id});
      await send(engine, const ShowHintEvent(questionId: 'q', shownHints: 0));
      expect(keyed(), {questionPicture.id, hintPicture.id});
      await send(engine, const RevealRoundEvent());
      expect(keyed(), contains(solutionPicture.id));
    });
  });

  group('guest', () {
    /// Serves the encrypted handles of [engine], failing [failures] times.
    var failed = 0;
    setUp(() => failed = 0);
    http.Client hostClient(QuizEngineBloc engine, {int failures = 0}) {
      return MockClient.streaming((request, _) async {
        if (failed < failures) {
          failed++;
          throw http.ClientException('Wi-Fi gone');
        }
        final id = request.url.pathSegments.last;
        final response = get(engine, id, range: request.headers['range']);
        return http.StreamedResponse(
          response.read(),
          response.statusCode,
          headers: response.headers,
        );
      });
    }

    test('downloads everything, opens only what has a key', () async {
      final engine = engineWith();
      addTearDown(engine.close);
      final preloader = MediaPreloader(
        createClient: () => hostClient(engine, failures: 1),
        retryDelay: const Duration(milliseconds: 10),
      );
      addTearDown(preloader.dispose);
      final phases = <MediaPreloadPhase>[];
      preloader.changes.listen((status) => phases.add(status.phase));
      preloader.offer(
        engine.mediaPreload.manifest,
        Uri.parse('http://localhost:8080'),
      );
      await preloader.changes
          .firstWhere((s) => s.phase == MediaPreloadPhase.done)
          .timeout(const Duration(seconds: 5));
      expect(phases, contains(MediaPreloadPhase.failed));
      expect(preloader.status.loadedFiles, 3);
      expect(preloader.status.fraction, 1);

      final reference = MediaAsset(
        id: questionPicture.id,
        mimeType: questionPicture.mimeType,
      );
      expect(await preloader.take(reference), isNull);
      await send(engine, const StartRoundEvent('q'));
      preloader.addKeys(engine.mediaPreload.keysFor(engine.publishedGame));
      final opened = await preloader.take(reference);
      expect(opened!.bytes, questionPicture.bytes);
      expect(
        await preloader.take(
          MediaAsset(id: solutionPicture.id, mimeType: 'image/svg+xml'),
        ),
        isNull,
      );
      // A forged key does not open anything.
      preloader.addKeys([
        MediaPreloadKey(
          handle: engine.mediaPreload.manifest.items.first.handle,
          assetId: solutionPicture.id,
          key: base64Encode(Uint8List(32)),
        ),
      ]);
      expect(
        await preloader.take(
          MediaAsset(id: solutionPicture.id, mimeType: 'image/svg+xml'),
        ),
        isNull,
      );
    });

    test('switched off, nothing is downloaded', () async {
      final engine = engineWith();
      addTearDown(engine.close);
      var requests = 0;
      final preloader = MediaPreloader(
        createClient: () => MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      )..setEnabled(false);
      addTearDown(preloader.dispose);
      preloader.offer(
        engine.mediaPreload.manifest,
        Uri.parse('http://localhost:8080'),
      );
      await pumpEventQueue();
      expect(requests, 0);
      expect(preloader.status.phase, MediaPreloadPhase.disabled);
    });

    test('the media cache takes preloaded media without a download', () async {
      final engine = engineWith();
      addTearDown(engine.close);
      final preloader = MediaPreloader(createClient: () => hostClient(engine));
      addTearDown(preloader.dispose);
      preloader.offer(
        engine.mediaPreload.manifest,
        Uri.parse('http://localhost:8080'),
      );
      await preloader.changes.firstWhere(
        (s) => s.phase == MediaPreloadPhase.done,
      );
      await send(engine, const StartRoundEvent('q'));
      preloader.addKeys(engine.mediaPreload.keysFor(engine.publishedGame));
      var downloads = 0;
      final cache = SessionMediaCache(
        baseUri: Uri.parse('http://localhost:8080'),
        preloader: preloader,
        createClient: () => MockClient((_) async {
          downloads++;
          return http.Response('', 404);
        }),
      );
      addTearDown(cache.dispose);
      final loaded = await cache.load(
        MediaAsset(id: questionPicture.id, mimeType: questionPicture.mimeType),
      );
      expect(sha256.convert(loaded.bytes!).toString(), questionPicture.id);
      expect(downloads, 0);
    });
  });

  test('a real host offers, keys and hears the progress of a player', () async {
    final engine = engineWith();
    final server = EmbeddedServer(engine: engine);
    final endpoint = await server.start(port: 0);
    final client = QuizClient(baseUri: endpoint.loopbackUri);
    final preloader = MediaPreloader();
    final link = MediaPreloadLink(preloader);
    addTearDown(() async {
      link.dispose();
      preloader.dispose();
      await client.dispose();
      await server.stop();
      await engine.close();
    });
    link.attach(client);
    await client.connect(name: 'Ada', handshakeProbes: 1);
    await preloader.changes
        .firstWhere((s) => s.phase == MediaPreloadPhase.done)
        .timeout(const Duration(seconds: 10));
    final reported = await engine.mediaPreloadStatuses.changes
        .map((_) => engine.mediaPreloadStatuses.all.values.single)
        .firstWhere((d) => d.status.phase == MediaPreloadPhase.done)
        .timeout(const Duration(seconds: 5));
    expect(reported.name, 'Ada');
    expect(reported.tv, isFalse);

    final shown = client.snapshots.firstWhere(
      (s) => s.mediaKeys.any((k) => k.assetId == questionPicture.id),
    );
    engine.add(const StartRoundEvent('q'));
    final snapshot = await shown.timeout(const Duration(seconds: 5));
    expect(
      snapshot.mediaKeys.map((k) => k.assetId),
      isNot(contains(solutionPicture.id)),
    );
    await pumpEventQueue();
    final opened = await preloader.take(
      MediaAsset(id: questionPicture.id, mimeType: questionPicture.mimeType),
    );
    expect(opened?.bytes, questionPicture.bytes);
  });
}
