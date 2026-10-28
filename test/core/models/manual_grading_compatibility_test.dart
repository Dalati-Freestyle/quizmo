import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';

File fixture(String name) =>
    File.fromUri(Uri(pathSegments: ['test', 'fixtures', name]));

void main() {
  for (final name in [
    'quiz_v1_before_media.quizmo.json',
    'quiz_v1_with_media.quizmo.json',
    'quiz_v2_with_media.quizmo.json',
    'quiz_v3_with_media.quizmo.json',
    'quiz_v4_with_media.quizmo.json',
    'quiz_v5_short_answer.quizmo.json',
  ]) {
    test('imports and re-exports historical fixture $name', () {
      final quiz = parseQuizImport(fixture(name).readAsStringSync());
      expect(quiz.schemaVersion, 6);
      expect(quiz.questions.every((q) => !q.requiresManualGrading), isTrue);
      final exported = exportQuizJson(quiz);
      expect(jsonDecode(exported)['schemaVersion'], 6);
      expect(parseQuizImport(exported), quiz);
    });
  }

  test(
    'schema 6 preserves manual grading and uploaded question/solution media',
    () {
      final old = parseQuizImport(
        fixture('quiz_v5_short_answer.quizmo.json').readAsStringSync(),
      );
      final question = Question.fromJson({
        ...old.questions.single.toJson(),
        'manualGrading': true,
      });
      final quiz = old.copyWith(questions: [question]);
      final restored = parseQuizImport(exportQuizJson(quiz));
      expect(restored, quiz);
      expect(restored.questions.single.requiresManualGrading, isTrue);
      expect(
        restored.questions.single.media.single.asset!.bytes,
        old.questions.single.media.single.asset!.bytes,
      );
      expect(
        restored.questions.single.solutionMedia.single.asset!.bytes,
        old.questions.single.solutionMedia.single.asset!.bytes,
      );
      final hidden = question.forWire(reveal: false);
      expect(hidden.requiresManualGrading, isTrue);
      expect(hidden.hasSolution, isFalse);
      expect(hidden.solutionMedia, isEmpty);
      expect((hidden as ShortAnswerQuestion).acceptedAnswers, isNull);
    },
  );

  test('older schemas always migrate short answers to automatic grading', () {
    final source = jsonDecode(
      fixture('quiz_v5_short_answer.quizmo.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final version in [1, 2, 3, 4, 5]) {
      source['schemaVersion'] = version;
      (source['questions'] as List).single['manualGrading'] = true;
      final quiz = parseQuizImport(jsonEncode(source));
      expect(quiz.questions.single.requiresManualGrading, isFalse);
    }
  });

  test('invalid grading mode leaves the persisted library untouched', () async {
    final original = parseQuizImport(
      fixture('quiz_v5_short_answer.quizmo.json').readAsStringSync(),
    );
    final repository = InMemoryQuizRepository([original]);
    final json = original.toJson();
    final question = (json['questions'] as List).single as JsonMap;
    question['manualGrading'] = 'manual';
    await expectLater(
      importQuiz(
        contents: jsonEncode(json),
        repository: repository,
        createId: () => 'unused',
      ),
      throwsA(isA<QuizImportException>()),
    );
    expect(await repository.loadAll(), [original]);
  });
}
