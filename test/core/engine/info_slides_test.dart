/// Interstitial slides (quiz schema 12).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const first = TrueFalseQuestion(id: 'q1', prompt: 'One?', correctAnswer: true);
const second = TrueFalseQuestion(id: 'q2', prompt: 'Two?', correctAnswer: true);
const pause = InfoSlide(
  id: 'pause',
  title: 'Trinkpause',
  beforeQuestionId: 'q2',
);
const end = InfoSlide(id: 'end', title: 'Das Ergebnis ist unterwegs!');

Quiz quizWith(List<InfoSlide> slides) => Quiz(
  id: 'quiz',
  name: 'Slides',
  description: 'Slides',
  category: 'Tests',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: const [first, second],
  slides: slides,
);

void main() {
  test('slides sit before their question, the others at the end', () {
    expect(
      interleaveSlides(const [first, second], const [end, pause], (q) => q.id),
      [first, pause, second, end],
    );
  });

  group('quiz file', () {
    test('round-trips slides with media', () {
      final image = ImageAttachment(
        asset: MediaAsset.upload(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]),
          'png',
        ),
      );
      final quiz = quizWith([
        pause.copyWith(media: [image], text: 'Prost!'),
        end,
      ]);
      final restored = parseQuizImport(exportQuizJson(quiz));
      expect(restored.slides, quiz.slides);
    });

    test('validates content and position', () {
      expect(quizWith(const [InfoSlide(id: 'x')]).validationErrors(), [
        'Eine Zwischenfolie braucht einen Titel, einen Text oder ein Medium.',
      ]);
      expect(
        quizWith(const [
          InfoSlide(id: 'x', title: 'X', beforeQuestionId: 'missing'),
        ]).validationErrors(),
        isNotEmpty,
      );
      expect(quizWith(const [end, end]).validationErrors(), isNotEmpty);
    });

    test('schema 11 files have no slides', () {
      final json = jsonDecode(
        exportQuizJson(quizWith(const [end])),
      ) as Map<String, Object?>;
      json['schemaVersion'] = 11;
      expect(
        () => parseQuizImport(jsonEncode(json)),
        throwsA(isA<QuizImportException>()),
      );
    });
  });

  group('engine', () {
    late QuizEngineBloc engine;
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    setUp(() async {
      engine = QuizEngineBloc(
        questionBank: const [first, second],
        slides: const [pause, end],
        now: () => 1000,
      );
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
    });
    tearDown(() => engine.close());

    test('shows a slide between questions and hides it on the next', () async {
      await send(const ShowSlideEvent('pause'));
      final game = engine.state.game;
      expect(game.activeSlide, pause);
      expect(game.showsSlide, isTrue);
      expect(game.shownSlideIds, {'pause'});
      final snapshot = game.redactedForPlayers();
      expect(snapshot.activeSlide, pause);
      expect(snapshot.slides, isEmpty);
      await send(const StartRoundEvent('q1'));
      expect(engine.state.game.activeSlide, isNull);
    });

    test('no slide while a question is running', () async {
      await send(const StartRoundEvent('q1'));
      await send(const ShowSlideEvent('pause'));
      expect(engine.state.game.activeSlide, isNull);
      await send(const RevealRoundEvent());
      await send(const ShowSlideEvent('end'));
      expect(engine.state.game.showsSlide, isTrue);
      await send(const HideSlideEvent());
      expect(engine.state.game.activeSlide, isNull);
    });

    test('unknown slides are ignored and reset clears the slide', () async {
      await send(const ShowSlideEvent('nope'));
      expect(engine.state.game.activeSlide, isNull);
      await send(const ShowSlideEvent('end'));
      await send(const ResetGameEvent());
      expect(engine.state.game.activeSlide, isNull);
      expect(engine.state.game.slides, const [pause, end]);
    });

    test('the slide survives JSON', () async {
      await send(const ShowSlideEvent('end'));
      final json = jsonDecode(jsonEncode(engine.state.game.toJson()));
      final restored = GameState.fromJson(json as JsonMap);
      expect(restored.activeSlide, end);
      expect(restored.slides, const [pause, end]);
    });
  });
}
