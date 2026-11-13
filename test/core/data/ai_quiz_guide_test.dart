/// Keeps the AI quiz guides (`docs/ai-quiz-guide.md` in German and
/// `docs/ai-quiz-guide.en.md` in English) importable.
///
/// The guides are shipped in the app as assets. Their example files are the
/// test fixtures: every block fenced with ```` ```json quizmo-example ````
/// must import without validation errors. A schema bump fails this test until
/// both guides describe the new schema.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

/// Guide path → sentence that names the schema version.
const _guides = {
  'docs/ai-quiz-guide.md': 'Schema-Version dieser Anleitung:',
  'docs/ai-quiz-guide.en.md': 'schema version of this guide:',
};

void main() {
  for (final MapEntry(key: path, value: versionSentence) in _guides.entries) {
    group(path, () {
      final guide = File(path).readAsStringSync();
      final examples = RegExp(r'```json quizmo-example\r?\n([\s\S]*?)\r?\n```')
          .allMatches(guide)
          .map((match) => match.group(1)!)
          .toList();

      test('describes the current schema version', () {
        expect(
          guide,
          contains('$versionSentence **${Quiz.currentSchemaVersion}**'),
          reason:
              'Quiz.currentSchemaVersion changed: update $path '
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

      test('lists every team colour by name and no colour codes', () {
        for (final color in TeamColor.values) {
          expect(guide, contains('`${color.name}`'));
        }
        expect(guide, isNot(contains('colorValue')));
      });

      test('the app ships the repository file as its only copy', () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('- $path'));
        final name = path.split('/').last;
        expect(
          Directory('assets')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith(name)),
          isEmpty,
        );
      });
    });
  }

  test('both guides contain the same examples apart from the texts', () {
    String shape(String path) =>
        RegExp(r'"(schemaVersion|type|color)": "?\w+')
            .allMatches(File(path).readAsStringSync())
            .map((match) => match.group(0))
            .join(',');
    expect(shape('docs/ai-quiz-guide.en.md'), shape('docs/ai-quiz-guide.md'));
  });
}
