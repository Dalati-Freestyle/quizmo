import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final media = ImageAttachment(
    asset: MediaAsset.upload(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      'png',
    ),
  );
  final question = BuzzerQuestion(
    id: 'q',
    prompt: 'Question',
    expectedAnswer: 'Secret',
    hostEndsRound: true,
    retryLimit: 2,
    lockOutOnMiss: false,
    media: [media],
    solutionMedia: [media],
  );
  final quiz = Quiz(
    id: 'quiz',
    name: 'Quiz',
    description: 'Test',
    category: 'Test',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    questions: [question],
  );

  test('schema 4 round-trips settings and both media sides', () {
    final restored = parseQuizImport(exportQuizJson(quiz));
    expect(restored, quiz);
    expect(restored.schemaVersion, 4);
    final hidden = restored.questions.single.redacted() as BuzzerQuestion;
    expect(hidden.retryLimit, 2);
    expect(hidden.hostEndsRound, isTrue);
    expect(hidden.solutionMedia, isEmpty);
    expect(hidden.expectedAnswer, isNull);
  });

  for (final version in [1, 2, 3]) {
    test('fixed schema $version fixture retains solutions and media', () {
      final restored = parseQuizImport(
        File('test/fixtures/quiz_v${version}_with_media.quizmo.json')
            .readAsStringSync(),
      );
      expect(restored.schemaVersion, 4);
      expect(restored.questions.first.media.single.asset!.bytes, isNotEmpty);
      expect(
        restored.questions.first.solutionMedia.single.asset!.bytes,
        isNotEmpty,
      );
      expect(parseQuizImport(exportQuizJson(restored)), restored);
      for (final old in restored.questions.whereType<BuzzerQuestion>()) {
        expect(old.hostEndsRound, isFalse);
        expect(old.retryLimit, isNull);
      }
    });
  }

  for (final invalid in [-1, 1.5, '2']) {
    test(
      'invalid retry count $invalid leaves stored quizzes untouched',
      () async {
        final repository = InMemoryQuizRepository([quiz]);
        final invalidQuiz = quiz.toJson();
        invalidQuiz['questions'] = [
          {...question.toJson(), 'retryLimit': invalid},
        ];
        await expectLater(
          importQuiz(
            contents: jsonEncode(invalidQuiz),
            repository: repository,
            createId: () => 'new',
          ),
          throwsA(isA<QuizImportException>()),
        );
        expect(await repository.loadAll(), [quiz]);
      },
    );
  }
}
