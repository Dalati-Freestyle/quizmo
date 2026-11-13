/// Keeps the AI quiz guide (`docs/ai-quiz-guide.md`) importable.
///
/// The guide is shipped in the app as an asset. Its example files are the test
/// fixtures: every block fenced with ```` ```json quizmo-example ```` must
/// import without validation errors. A schema bump fails this test until the
/// guide describes the new schema.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

const _guidePath = 'docs/ai-quiz-guide.md';

void main() {
  final guide = File(_guidePath).readAsStringSync();
  final examples = RegExp(r'```json quizmo-example\r?\n([\s\S]*?)\r?\n```')
      .allMatches(guide)
      .map((match) => match.group(1)!)
      .toList();

  test('the guide describes the current schema version', () {
    expect(
      guide,
      contains(
        'Schema-Version dieser Anleitung: **${Quiz.currentSchemaVersion}**',
      ),
      reason:
          'Quiz.currentSchemaVersion changed: update docs/ai-quiz-guide.md '
          '(format description and examples) to the new schema.',
    );
    expect(
      RegExp(r'"schemaVersion": (\d+)')
          .allMatches(guide)
          .map((match) => int.parse(match.group(1)!))
          .toSet(),
      {Quiz.currentSchemaVersion},
    );
  });

  test('every example imports without validation errors', () {
    expect(examples, hasLength(greaterThanOrEqualTo(3)));
    for (final example in examples) {
      final quiz = parseQuizImport(example);
      expect(quiz.validationErrors(), isEmpty, reason: quiz.name);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
    }
  });

  test('the examples cover every format and every question type', () {
    final quizzes = examples.map(parseQuizImport).toList();
    expect(quizzes.map((quiz) => quiz.format.runtimeType).toSet(), {
      StandardFormat,
      JeopardyFormat,
      PokerFormat,
    });
    final kinds = {
      for (final quiz in quizzes)
        for (final question in quiz.questions)
          switch (question) {
            MultipleChoiceQuestion() => 'multipleChoice',
            BuzzerQuestion() => 'buzzer',
            ShortAnswerQuestion() => 'shortAnswer',
            OrderingQuestion() => 'ordering',
            MatchingQuestion() => 'matching',
            EstimationQuestion() => 'estimation',
            TrueFalseQuestion() => 'trueFalse',
          },
    };
    expect(kinds, hasLength(7));
    for (final kind in kinds) {
      expect(guide, contains('`$kind`'), reason: 'type table lists $kind');
    }
  });

  test('the app ships the repository file as its only copy', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- $_guidePath'));
    expect(
      Directory('assets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('ai-quiz-guide.md')),
      isEmpty,
    );
  });
}
