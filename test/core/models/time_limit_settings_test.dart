import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  test('all question kinds preserve soft limits through wire redaction', () {
    for (final original in sampleDemoQuestionBank) {
      final question = Question.fromJson({
        ...original.toJson(),
        'softTimeLimit': true,
      });
      expect(question.softTimeLimit, isTrue);
      expect(question.redacted().softTimeLimit, isTrue);
      expect(question.forWire(reveal: false).softTimeLimit, isTrue);
      expect(Question.fromJson(question.toJson()), question);
      expect(question, isNot(original));
    }
  });

  test(
    'schema 1 through 4 keep hard limits, solutions and both media sides',
    () {
      for (final version in [1, 2, 3, 4]) {
        final quiz = parseQuizImport(
          File('test/fixtures/quiz_v${version}_with_media.quizmo.json')
              .readAsStringSync(),
        );
        expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
        expect(quiz.questions.every((q) => !q.softTimeLimit), isTrue);
        expect(quiz.questions.first.hasSolution, isTrue);
        expect(quiz.questions.first.media, isNotEmpty);
        expect(quiz.questions.first.solutionMedia, isNotEmpty);
        expect(parseQuizImport(exportQuizJson(quiz)), quiz);
      }
    },
  );

  test('soft audio limits survive export and wire serialization', () {
    final original = sampleDemoQuestionBank
        .expand((q) => q.media)
        .whereType<AudioAttachment>()
        .first;
    final soft = MediaAttachment.fromJson({
      ...original.toJson(),
      'softPlaybackLimit': true,
    }) as AudioAttachment;
    expect(soft.softPlaybackLimit, isTrue);
    expect(
      (MediaAttachment.fromJson(
        soft.forWire(),
      ) as AudioAttachment).softPlaybackLimit,
      isTrue,
    );
    expect(soft.playbackLimitSeconds, original.playbackLimitSeconds);
  });
}
