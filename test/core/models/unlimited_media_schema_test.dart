/// Quiz schema 11 lifts the 20 MiB per file and 90 MiB per quiz media limits.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  test('schema 11 is current', () {
    expect(Quiz.currentSchemaVersion, 11);
  });

  test('a schema 10 file with media imports and is saved as schema 11', () {
    final contents = File('test/fixtures/quiz_v10_with_media.quizmo.json')
        .readAsStringSync();
    final quiz = parseQuizImport(contents);
    expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
    final question = quiz.questions.single;
    expect(question.media.single.asset!.mimeType, 'image/svg+xml');
    expect(question.solutionMedia.single.caption, 'Answer');
    final exported = exportQuizJson(quiz);
    expect(jsonDecode(exported)['schemaVersion'], Quiz.currentSchemaVersion);
    expect(parseQuizImport(exported), quiz);
  });

  test('an older app is asked to update for schema 12 files', () {
    expect(
      () => parseQuizImport(
        jsonEncode({'schemaVersion': Quiz.currentSchemaVersion + 1}),
      ),
      throwsA(isA<QuizImportUpdateRequiredException>()),
    );
  });
}
