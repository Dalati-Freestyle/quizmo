import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/engine/answer_evaluation.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';

EstimationQuestion question({
  double target = 330,
  double? min = 320,
  double? max = 340,
  String unit = 'm',
  bool toleranceOnly = false,
}) => EstimationQuestion(
  id: 'q',
  prompt: 'Eiffelturm?',
  correctValue: target,
  minAccepted: min,
  maxAccepted: max,
  unit: unit,
  toleranceOnly: toleranceOnly,
  timeLimit: Duration.zero,
);

EstimationAnswer answer(double value, {String player = 'p'}) =>
    EstimationAnswer(
      playerId: player,
      questionId: 'q',
      clientTimestampMicros: 0,
      clockOffsetMicros: 0,
      value: value,
    );

void main() {
  test('the limits belong to the range, nothing outside is fully correct', () {
    final q = question();
    for (final value in [320.0, 327.0, 330.0, 340.0]) {
      expect(q.accuracy(answer(value)), 1, reason: '$value');
    }
    for (final value in [319.999999, 340.000001, 319.0, 1e9, -330.0]) {
      expect(q.accuracy(answer(value)), lessThan(1), reason: '$value');
    }
    expect(q.accuracy(answer(319)), closeTo(1 - 11 / 330, 1e-9));
    // Even when rounding would make the partial score 1.
    final huge = question(target: 1e300, min: 1e300, max: 1e300);
    expect(huge.accuracy(answer(1e300)), 1);
    expect(huge.accuracy(answer(1e300 * (1 + 4e-16))), lessThan(1));
  });

  test('without tolerance the scoring is unchanged', () {
    final q = question(min: null, max: null);
    for (final value in [330.0, 320.0, 0.0, 700.0]) {
      expect(q.accuracy(answer(value)), estimationAccuracy(value, 330, 1));
    }
  });

  test('negative, decimal and zero targets work', () {
    final zero = question(target: 0, min: -0.5, max: 0.25);
    expect(zero.contentErrors, isEmpty);
    expect(zero.accuracy(answer(-0.5)), 1);
    expect(zero.accuracy(answer(0.26)), closeTo(0.74, 1e-9));
    final negative = question(target: -40, min: -42, max: -38);
    expect(negative.accuracy(answer(-42)), 1);
    expect(negative.accuracy(answer(-42.1)), lessThan(1));
  });

  test('invalid ranges are reported', () {
    expect(question(max: null).contentErrors, hasLength(1));
    expect(question(min: null).contentErrors, hasLength(1));
    expect(question(min: 341).contentErrors, hasLength(1));
    expect(question(min: 331).contentErrors, hasLength(1));
    expect(question().contentErrors, isEmpty);
  });

  test('whole numbers are shown without a fraction', () {
    expect(question().solutionLabel, '330 m (320 – 340 m)');
    expect(question(min: null, max: null, unit: '').solutionLabel, '330');
    expect(formatNumber(1.5), '1.5');
    expect(formatNumber(-0.0), '0');
  });

  test('the range stays secret until the reveal', () {
    final redacted = question().redacted();
    expect(redacted.hasTolerance, isFalse);
    expect(jsonEncode(redacted.toJson()), isNot(contains('Accepted')));
    expect(
      jsonEncode(question().forWire(reveal: false).toJson()),
      isNot(contains('Accepted')),
    );
    expect(question().forWire(reveal: true), question());
  });

  test('bots never guess wrong inside the range', () {
    for (final q in [
      question(),
      question(target: 10, min: -20, max: 20),
      question(target: 0, min: -5, max: 5),
      question(target: -10, min: -20, max: 1),
    ]) {
      for (final correct in [true, false]) {
        final bot = botAnswer(q, playerId: 'p', timestamp: 0, correct: correct);
        expect(q.accuracy(bot), correct ? 1 : 0);
      }
    }
  });

  test('poker pays every answer in the range', () async {
    final engine = QuizEngineBloc(
      questionBank: [question()],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      pokerStartingChips: 100,
    );
    addTearDown(engine.close);
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    for (final id in ['a', 'b']) {
      await send(PlayerJoinedEvent(Player(id: 'p$id', name: id, teamId: id)));
    }
    await send(const StartRoundEvent('q'));
    for (final id in ['a', 'b']) {
      await send(
        PlacePokerWagerEvent(playerId: 'p$id', questionId: 'q', wager: 40),
      );
    }
    await send(const OpenPokerAnswersEvent());
    await send(SubmitAnswerEvent(answer(340, player: 'pa')));
    await send(SubmitAnswerEvent(answer(341, player: 'pb')));
    await send(const RevealRoundEvent());
    expect(engine.state.game.poker!.chips, {'a': 140, 'b': 60});
  });

  group('tolerance only', () {
    test('scores the range fully and everything else with nothing', () {
      final q = question(toleranceOnly: true);
      for (final value in [320.0, 330.0, 340.0]) {
        expect(q.accuracy(answer(value)), 1, reason: '$value');
      }
      for (final value in [319.9, 340.1, 0.0, 1e9]) {
        expect(q.accuracy(answer(value)), 0, reason: '$value');
      }
    });

    test('needs both limits and ignores the zero scale', () {
      expect(
        question(toleranceOnly: true, min: null, max: null).solutionErrors,
        hasLength(1),
      );
      expect(question(toleranceOnly: true).contentErrors, isEmpty);
      expect(question(target: 0).usesZeroScale, isTrue);
      expect(question(target: 655).usesZeroScale, isFalse);
      expect(question(target: 0, toleranceOnly: true).usesZeroScale, isFalse);
    });

    test('is public, round-trips and stays out of older files', () {
      final q = question(toleranceOnly: true);
      expect(q.redacted().toleranceOnly, isTrue);
      expect(Question.fromJson(q.toJson()), q);
      expect(question().toJson(), isNot(contains('toleranceOnly')));
    });

    test('schema 16 imports unchanged and may not use the mode', () {
      final source = File(
        p.join('test', 'fixtures', 'quiz_v16_with_media.quizmo.json'),
      ).readAsStringSync();
      final quiz = parseQuizImport(source);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      final estimation = quiz.questions.whereType<EstimationQuestion>().last;
      expect(estimation.toleranceOnly, isFalse);
      expect(estimation.maxAccepted, 340);
      expect(quiz.questions.whereType<LocationQuestion>(), hasLength(1));
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
      final json = jsonDecode(source) as JsonMap;
      ((json['questions'] as List).last as JsonMap)['toleranceOnly'] = true;
      expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
      final current = Quiz.fromJson({...json, 'schemaVersion': 17});
      expect(
        (current.questions.last as EstimationQuestion).toleranceOnly,
        isTrue,
      );
      expect(
        parseQuizImport(exportQuizJson(current)).questions,
        current.questions,
      );
    });
  });

  group('schema 13', () {
    final source = File(
      p.join('test', 'fixtures', 'quiz_v13_with_media.quizmo.json'),
    ).readAsStringSync();

    test('imports without a tolerance and keeps hints and media', () {
      final quiz = parseQuizImport(source);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      final estimation = quiz.questions.whereType<EstimationQuestion>().single;
      expect(estimation.hasTolerance, isFalse);
      expect(quiz.questions.first.hints.single.cost, 2);
      expect(quiz.questions.first.media.single.asset!.bytes, isNotEmpty);
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
    });

    test('may not contain a tolerance; schema 14 round-trips it', () {
      final json = jsonDecode(source) as JsonMap;
      final estimation = (json['questions'] as List).last as JsonMap;
      estimation['minAccepted'] = 320;
      estimation['maxAccepted'] = 340;
      expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
      final quiz = Quiz.fromJson({...json, 'schemaVersion': 14});
      expect((quiz.questions.last as EstimationQuestion).maxAccepted, 340);
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
    });
  });
}
