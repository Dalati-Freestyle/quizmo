import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  for (final name in [
    'quiz_v1_before_media.quizmo.json',
    'quiz_v1_with_media.quizmo.json',
    'quiz_v2_with_media.quizmo.json',
    'quiz_v3_with_media.quizmo.json',
    'quiz_v4_with_media.quizmo.json',
    'quiz_v5_short_answer.quizmo.json',
    'quiz_v6_manual_grading.quizmo.json',
  ]) {
    test('historical fixture $name retains its original reveal behavior', () {
      final contents = File.fromUri(
        Uri(pathSegments: ['test', 'fixtures', name]),
      ).readAsStringSync();
      final quiz = parseQuizImport(contents);
      if (quiz.format case StandardFormat(:final revealMode)) {
        expect(revealMode, SolutionRevealMode.afterEachQuestion);
      }
      if (name.startsWith('quiz_v6')) {
        expect(quiz.questions.single.requiresManualGrading, isTrue);
      }
      expect(quiz.schemaVersion, 7);
      expect(parseQuizImport(exportQuizJson(quiz)), quiz);
    });
  }

  test(
    'latest schema round-trips both modes including manual grading/media',
    () {
      final old = parseQuizImport(
        File.fromUri(
          Uri(
            pathSegments: [
              'test',
              'fixtures',
              'quiz_v6_manual_grading.quizmo.json',
            ],
          ),
        ).readAsStringSync(),
      );
      for (final mode in SolutionRevealMode.values) {
        final source = old.copyWith(format: StandardFormat(revealMode: mode));
        final exported = exportQuizJson(source);
        expect(jsonDecode(exported)['schemaVersion'], 7);
        final restored = parseQuizImport(exported);
        expect(restored, source);
        expect(
          restored.questions.single.media.single.asset!.bytes,
          old.questions.single.media.single.asset!.bytes,
        );
        expect(
          restored.questions.single.solutionMedia.single.asset!.bytes,
          old.questions.single.solutionMedia.single.asset!.bytes,
        );
      }
    },
  );

  test('invalid reveal mode never touches persistence', () async {
    final quiz = Quiz(
      id: 'q',
      name: 'Quiz',
      description: 'Description',
      category: 'Test',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final repository = InMemoryQuizRepository([quiz]);
    final json = quiz.toJson()
      ..['format'] = {'type': 'standard', 'revealMode': 'unknown'};
    await expectLater(
      importQuiz(
        contents: jsonEncode(json),
        repository: repository,
        createId: () => 'unused',
      ),
      throwsA(isA<QuizImportException>()),
    );
    expect(await repository.loadAll(), [quiz]);
  });
}
