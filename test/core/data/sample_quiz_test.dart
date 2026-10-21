import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 22);
  final examples = createSampleQuizzes(timestamp);

  test('one complete example per format with stable unique IDs', () {
    expect(examples.map((q) => q.id).toSet(), hasLength(3));
    expect(examples.map((q) => q.format.runtimeType).toSet(), {
      StandardFormat,
      JeopardyFormat,
      PokerFormat,
    });
    for (final quiz in examples) {
      expect(quiz.validationErrors(), isEmpty, reason: quiz.name);
      expect(quiz.questions, hasLength(12));
      expect(quiz.createdAt, timestamp);
      expect(quiz.updatedAt, timestamp);
      expect(quiz.teams.length, greaterThanOrEqualTo(2));
      expect(quiz.questions.map((q) => q.runtimeType).toSet(), {
        MultipleChoiceQuestion,
        BuzzerQuestion,
        ShortAnswerQuestion,
        OrderingQuestion,
        MatchingQuestion,
        EstimationQuestion,
        TrueFalseQuestion,
      });
      expect(quiz.questions.every((q) => q.adminNotes.isNotEmpty), isTrue);
      expect(quiz.questions.every((q) => q.hasSolution), isTrue);
      final restored = Quiz.fromJson(
        jsonDecode(jsonEncode(quiz.toJson())) as Map<String, dynamic>,
      );
      expect(restored, quiz);
    }
  });

  for (final quiz in examples) {
    test('${quiz.format.label} covers media and question settings', () {
      final questions = quiz.questions;
      final attachments = questions
          .expand((q) => [...q.media, ...q.solutionMedia])
          .toList();
      expect(attachments.map((m) => m.runtimeType).toSet(), {
        ImageAttachment,
        AudioAttachment,
        VideoAttachment,
        CodeAttachment,
        GeoAttachment,
      });
      expect(
        attachments
            .whereType<VideoAttachment>()
            .map((m) => m.hideDetails)
            .toSet(),
        {false, true},
      );
      expect(
        attachments.whereType<ImageAttachment>().map((m) => m.zoom).toSet(),
        {false, true},
      );
      expect(
        attachments.whereType<AudioAttachment>().any(
          (m) => m.playbackLimitSeconds != null,
        ),
        isTrue,
      );
      expect(
        attachments.whereType<AudioAttachment>().any(
          (m) => m.playbackLimitSeconds == null,
        ),
        isTrue,
      );
      for (final attachment in attachments) {
        expect(attachment.validationErrors, isEmpty);
        final asset = attachment.asset;
        if (asset != null) {
          expect(asset.data, isNotEmpty);
          expect(asset.validate, returnsNormally);
        }
      }
      expect(
        questions
            .whereType<MultipleChoiceQuestion>()
            .map((q) => q.allowMultipleAnswers)
            .toSet(),
        {false, true},
      );
      expect(
        questions
            .whereType<TrueFalseQuestion>()
            .map((q) => q.correctAnswer)
            .toSet(),
        {false, true},
      );
      expect(
        questions.whereType<EstimationQuestion>().any(
          (q) => q.correctValue == 0 && q.zeroScale != 1,
        ),
        isTrue,
      );
      expect(
        questions.whereType<ShortAnswerQuestion>().any(
          (q) => q.acceptedAnswers!.length > 1 && q.maxEdits > 0,
        ),
        isTrue,
      );
      final buzzers = questions.whereType<BuzzerQuestion>();
      expect(buzzers.map((q) => q.lockOutOnMiss).toSet(), {false, true});
      expect(buzzers.map((q) => q.hostEndsRound).toSet(), {false, true});
      expect(buzzers.any((q) => q.retryLimit != null), isTrue);
      expect(questions.map((q) => q.scoringRule.runtimeType).toSet(), {
        FixedPointsRule,
        SpeedBonusRule,
        FirstBuzzerRule,
      });
      for (final question in questions) {
        final hidden = question.forWire(reveal: false);
        expect(hidden.hasSolution, isFalse);
        expect(hidden.solutionMedia, isEmpty);
        expect(hidden.adminNotes, isEmpty);
        expect(hidden.media.every((m) => m.asset?.data == null), isTrue);
        expect(
          hidden.media
              .where((m) => m.hideDetails)
              .every((m) => m.caption.isEmpty),
          isTrue,
        );
        expect(
          question.forWire(reveal: true).solutionMedia,
          hasLength(question.solutionMedia.length),
        );
      }
    });
  }

  test(
    'Jeopardy places every question exactly once and enables format rules',
    () {
      final quiz = examples.singleWhere((q) => q.format is JeopardyFormat);
      final board = (quiz.format as JeopardyFormat).board;
      expect(
        board.questionIds.toList(),
        unorderedEquals(quiz.questions.map((q) => q.id)),
      );
      expect(board.rowPoints, [100, 200, 300, 400]);
      expect(board.allowSteal, isTrue);
      expect(board.penalizeWrongAnswers, isTrue);
      expect(
        board.categories.expand((c) => c.cells).where((c) => c.isDailyDouble),
        hasLength(1),
      );
      expect(
        board
            .redacted()
            .categories
            .expand((c) => c.cells)
            .any((c) => c.isDailyDouble),
        isFalse,
      );
    },
  );

  test('Poker uses a non-default starting chip balance', () {
    final poker =
        examples.singleWhere((q) => q.format is PokerFormat).format
            as PokerFormat;
    expect(poker.startingChips, 250);
  });

  test('generated audio is a complete two-second mono PCM WAV', () {
    final audio = examples.first.questions
        .expand((q) => q.media)
        .whereType<AudioAttachment>()
        .first;
    final bytes = audio.asset.bytes!;
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bytes.length, 44 + 16000 * 2 * 2);
    expect(bytes.sublist(44).any((value) => value != 0), isTrue);
  });
}
