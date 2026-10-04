/// Unit tests for standalone quiz import and export.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final quiz = Quiz(
    id: 'quiz-import',
    name: 'Importable quiz',
    description: 'For import tests.',
    category: 'Testing',
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
    questions: const [
      MultipleChoiceQuestion(
        id: 'question-1',
        prompt: 'Choose the valid option.',
        options: [
          AnswerOption(id: 'a', label: 'A'),
          AnswerOption(id: 'b', label: 'B'),
        ],
        correctOptionId: 'a',
        scoringRule: FixedPointsRule(),
      ),
    ],
  );

  test('imports a valid file and exports readable JSON', () async {
    final repository = InMemoryQuizRepository();
    final contents = exportQuizJson(quiz);

    final imported = await importQuiz(
      contents: contents,
      repository: repository,
      createId: () => 'unused',
    );

    expect(imported, quiz);
    expect(await repository.loadAll(), [quiz]);
    expect(contents, contains('\n  "schemaVersion": 1'));
  });

  test('rejects malformed JSON', () {
    expect(
      () => parseQuizImport('{not valid JSON'),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('not valid JSON'),
        ),
      ),
    );
  });

  test('rejects an unknown question type', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {...quiz.questions.single.toJson(), 'type': 'futureUnknownType'},
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unknown question type "futureUnknownType"'),
        ),
      ),
    );
  });

  test('rejects an unknown scoring rule', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {
          ...quiz.questions.single.toJson(),
          'scoringRule': {'type': 'mystery'},
        },
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unknown scoring rule "mystery"'),
        ),
      ),
    );
  });

  test('rejects an MC question without a valid correct option', () {
    final json = _jsonFor(quiz)
      ..['questions'] = [
        {
          ...quiz.questions.single.toJson(),
          'correctOptionId': 'missing-option',
        },
      ];

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('correctOptionId'),
        ),
      ),
    );
  });

  test('rejects an unsupported schema version', () {
    final json = _jsonFor(quiz)..['schemaVersion'] = 999;

    expect(
      () => parseQuizImport(jsonEncode(json)),
      throwsA(
        isA<QuizImportException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported quiz schemaVersion 999'),
        ),
      ),
    );
  });

  test('assigns a new ID instead of overwriting an existing quiz', () async {
    final repository = InMemoryQuizRepository([quiz]);

    final imported = await importQuiz(
      contents: exportQuizJson(quiz),
      repository: repository,
      createId: () => 'quiz-import-copy',
      now: () => DateTime.utc(2026, 9, 20),
    );

    expect(imported.id, 'quiz-import-copy');
    expect((await repository.loadAll()).map((item) => item.id), [
      'quiz-import',
      'quiz-import-copy',
    ]);
  });
}

Map<String, Object?> _jsonFor(Quiz quiz) =>
    Map<String, Object?>.from(quiz.toJson());
