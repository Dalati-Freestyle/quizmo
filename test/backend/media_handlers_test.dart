import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/media_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:shelf/shelf.dart';

void main() {
  MediaAsset svg(String color) => MediaAsset.upload(
    Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="$color"/></svg>',
      ),
    ),
    'svg',
  );
  test(
    'uploads reject scripts, external SVG references and spoofed formats',
    () {
      expect(
        () => MediaAsset.upload(
          Uint8List.fromList(
            utf8.encode('<svg><script>alert(1)</script></svg>'),
          ),
          'svg',
        ),
        throwsA(isA<JsonContractException>()),
      );
      expect(
        () => MediaAsset.upload(
          Uint8List.fromList(
            utf8.encode('<svg><use href="https://example.com"/></svg>'),
          ),
          'svg',
        ),
        throwsA(isA<JsonContractException>()),
      );
      expect(
        () => MediaAsset.upload(Uint8List.fromList([1, 2, 3]), 'png'),
        throwsA(isA<JsonContractException>()),
      );
      final asset = svg('red');
      expect(
        () => MediaAsset.fromJson({...asset.toJson(), 'id': '0' * 64}),
        throwsA(isA<JsonContractException>()),
      );
    },
  );
  test('HTTP only exposes current media; solutions wait for reveal; byte ranges work', () async {
    final image = svg('red');
    final solution = svg('blue');
    final future = svg('green');
    final engine = QuizEngineBloc(
      questionBank: [
        TrueFalseQuestion(
          id: 'q',
          prompt: 'True?',
          correctAnswer: true,
          media: [ImageAttachment(asset: image)],
          solutionMedia: [ImageAttachment(asset: solution)],
        ),
        TrueFalseQuestion(
          id: 'next',
          prompt: 'Next?',
          correctAnswer: false,
          media: [ImageAttachment(asset: future)],
        ),
      ],
    );
    addTearDown(engine.close);
    Response get(MediaAsset a, {String method = 'GET', String? range}) =>
        serveMedia(
          Request(
            method,
            Uri.parse('http://localhost/api/media/${a.id}'),
            headers: {'range': ?range},
          ),
          a.id,
          engine,
        );
    expect(get(image).statusCode, 404);
    engine.add(const StartRoundEvent('q'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(get(image).statusCode, 200);
    expect(get(solution).statusCode, 404);
    expect(get(future).statusCode, 404);
    final wire = engine.state.game.redactedForPlayers();
    expect(wire.round.question!.solutionMedia, isEmpty);
    expect(wire.round.question!.media.single.asset!.data, isNull);
    final range = get(image, range: 'bytes=0-3');
    expect(range.statusCode, 206);
    expect(
      await range.read().expand((chunk) => chunk).toList(),
      image.bytes!.take(4).toList(),
    );
    expect(get(image, range: 'bytes=-4').statusCode, 206);
    expect(get(image, range: 'bytes=9999-').statusCode, 416);
    expect(get(image, range: 'bytes=0-1,3-4').statusCode, 416);
    expect(await get(image, method: 'HEAD').readAsString(), '');
    expect(get(image, method: 'POST').statusCode, 405);
    engine.add(const RevealRoundEvent());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(get(solution).statusCode, 200);
    expect(
      engine.state.game
          .redactedForPlayers()
          .round
          .question!
          .solutionMedia
          .single
          .asset!
          .data,
      isNull,
    );
  });

  test('deferred solutions stay inaccessible until the final review, including past media', () async {
    final image = svg('red');
    final solution = svg('blue');
    final engine = QuizEngineBloc(
      revealMode: SolutionRevealMode.atEnd,
      questionBank: [
        TrueFalseQuestion(
          id: 'q',
          prompt: 'First?',
          correctAnswer: true,
          media: [ImageAttachment(asset: image)],
          solutionMedia: [ImageAttachment(asset: solution)],
        ),
        const TrueFalseQuestion(
          id: 'last',
          prompt: 'Last?',
          correctAnswer: false,
        ),
      ],
    );
    addTearDown(engine.close);
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    Response get(MediaAsset asset) => serveMedia(
      Request('GET', Uri.parse('http://localhost/api/media/${asset.id}')),
      asset.id,
      engine,
    );
    await send(const StartRoundEvent('q'));
    expect(get(image).statusCode, 200);
    expect(get(solution).statusCode, 404);
    await send(const RevealRoundEvent());
    expect(get(solution).statusCode, 404);
    await send(const NextQuestionEvent());
    expect(get(image).statusCode, 404);
    expect(get(solution).statusCode, 404);
    await send(const RevealRoundEvent());
    expect(get(image).statusCode, 200);
    expect(get(solution).statusCode, 200);
    await send(const CloseRoundEvent());
    expect(get(solution).statusCode, 200);
    await send(const ResetGameEvent());
    expect(get(image).statusCode, 404);
    expect(get(solution).statusCode, 404);
  });
}
