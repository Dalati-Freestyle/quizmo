import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

Map<String, Object?> _fixtureV7() => jsonDecode(
  File.fromUri(
    Uri(
      pathSegments: ['test', 'fixtures', 'quiz_v7_reveal_at_end.quizmo.json'],
    ),
  ).readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object?> _withLimit(
  Map<String, Object?> file,
  int timeLimitMs, {
  int? schemaVersion,
  Map<String, Object?>? scoringRule,
}) => {
  ...file,
  'schemaVersion': ?schemaVersion,
  'questions': [
    for (final question in file['questions']! as List<Object?>)
      {
        ...question! as Map<String, Object?>,
        'timeLimitMs': timeLimitMs,
        'scoringRule': ?scoringRule,
      },
  ],
};

void main() {
  test('a schema 7 file keeps its limit, reveal mode and media', () {
    final quiz = parseQuizImport(jsonEncode(_fixtureV7()));
    expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
    expect(
      quiz.format,
      const StandardFormat(revealMode: SolutionRevealMode.atEnd),
    );
    final question = quiz.questions.single;
    expect(question.timeLimit, const Duration(seconds: 30));
    expect(question.hasTimeLimit, isTrue);
    expect(question.media, hasLength(1));
    expect(question.solutionMedia, hasLength(1));
    expect(parseQuizImport(exportQuizJson(quiz)), quiz);
  });

  test('0 stays invalid in schema 7 files', () {
    expect(
      () => parseQuizImport(jsonEncode(_withLimit(_fixtureV7(), 0))),
      throwsA(isA<QuizImportException>()),
    );
  });

  test('schema 8 stores questions without a time limit as 0', () {
    final source = _withLimit(_fixtureV7(), 0, schemaVersion: 8);
    final quiz = parseQuizImport(jsonEncode(source));
    expect(quiz.questions.single.hasTimeLimit, isFalse);
    final exported = jsonDecode(exportQuizJson(quiz)) as Map<String, Object?>;
    expect(exported['schemaVersion'], Quiz.currentSchemaVersion);
    expect(((exported['questions']! as List).single as Map)['timeLimitMs'], 0);
    expect(parseQuizImport(jsonEncode(exported)), quiz);
  });

  test('negative limits and a speed bonus without a limit are invalid', () {
    expect(
      () => parseQuizImport(
        jsonEncode(_withLimit(_fixtureV7(), -1000, schemaVersion: 8)),
      ),
      throwsA(isA<QuizImportException>()),
    );
    expect(
      () => parseQuizImport(
        jsonEncode(
          _withLimit(
            _fixtureV7(),
            0,
            schemaVersion: 8,
            scoringRule: const SpeedBonusRule().toJson(),
          ),
        ),
      ),
      throwsA(isA<QuizImportException>()),
    );
  });

  test('a file from a newer schema asks for an update', () {
    expect(
      () => parseQuizImport(
        jsonEncode({
          ..._fixtureV7(),
          'schemaVersion': Quiz.currentSchemaVersion + 1,
        }),
      ),
      throwsA(isA<QuizImportUpdateRequiredException>()),
    );
  });

  group('engine without a time limit', () {
    late QuizEngineBloc engine;
    var now = 1700000000000000;

    setUp(() {
      now = 1700000000000000;
      engine = QuizEngineBloc(
        questionBank: const [
          TrueFalseQuestion(
            id: 'q',
            prompt: 'Q?',
            correctAnswer: true,
            timeLimit: Duration.zero,
          ),
        ],
        now: () => now,
      );
      addTearDown(engine.close);
    });

    test('the round stays open until the host ends it', () async {
      engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
      engine.add(const StartRoundEvent('q'));
      await pumpEventQueue();
      engine.add(const ExpireRoundEvent('q', 1700000000000000));
      await pumpEventQueue();
      expect(engine.state.game.round.status, RoundStatus.acceptingAnswers);
      now += const Duration(hours: 1).inMicroseconds;
      engine.add(
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: 'p',
            questionId: 'q',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
            value: true,
          ),
        ),
      );
      await pumpEventQueue();
      expect(engine.state.game.round.answers, contains('p'));
    });
  });
}
