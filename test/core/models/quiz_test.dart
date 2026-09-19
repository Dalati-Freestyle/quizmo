/// Unit tests for the persisted quiz aggregate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 19, 12);
  final updatedAt = DateTime.utc(2026, 9, 19, 13);
  final quiz = Quiz(
    id: 'quiz-history',
    name: 'History night',
    description: 'A small quiz covering different eras.',
    category: 'History',
    createdAt: createdAt,
    updatedAt: updatedAt,
    teams: const [
      Team(id: 'team-red', name: 'Red Foxes', colorValue: 0xFFE5484D),
    ],
    questions: const [
      MultipleChoiceQuestion(
        id: 'mc-fixed',
        prompt: 'Which century followed the eighteenth century?',
        options: [
          AnswerOption(id: 'a', label: '17th'),
          AnswerOption(id: 'b', label: '19th'),
        ],
        correctOptionId: 'b',
        scoringRule: FixedPointsRule(correctPoints: 8, wrongPoints: -2),
        timeLimit: Duration(seconds: 25),
      ),
      MultipleChoiceQuestion(
        id: 'mc-speed',
        prompt: 'Which city was ancient Rome?',
        options: [
          AnswerOption(id: 'a', label: 'Rome'),
          AnswerOption(id: 'b', label: 'Athens'),
        ],
        correctOptionId: 'a',
        scoringRule: SpeedBonusRule(
          basePoints: 8,
          maxSpeedBonus: 4,
          wrongPoints: -1,
        ),
      ),
      BuzzerQuestion(
        id: 'buzzer-first',
        prompt: 'Name the first emperor of Rome.',
        expectedAnswer: 'Augustus',
        scoringRule: FirstBuzzerRule(points: 15, penalty: -5, rankDecay: 3),
        timeLimit: Duration(seconds: 18),
      ),
    ],
  );

  group('Quiz JSON', () {
    test('round trips both question types and every scoring rule', () {
      final restored = Quiz.fromJson(quiz.toJson());

      expect(restored, quiz);
      expect(restored.questions.map((question) => question.runtimeType), [
        MultipleChoiceQuestion,
        MultipleChoiceQuestion,
        BuzzerQuestion,
      ]);
      expect(
        restored.questions.map((question) => question.scoringRule.runtimeType),
        [FixedPointsRule, SpeedBonusRule, FirstBuzzerRule],
      );
    });

    test('rejects an MC question whose correct option is missing', () {
      final json = quiz.toJson();
      final questions = List<Object?>.from(json['questions']! as List<Object?>);
      final firstQuestion = Map<String, Object?>.from(
        questions.first! as Map<String, Object?>,
      )..['correctOptionId'] = 'does-not-exist';
      questions[0] = firstQuestion;
      json['questions'] = questions;

      expect(
        () => Quiz.fromJson(json),
        throwsA(
          isA<QuizValidationException>().having(
            (error) => error.messages.join(' '),
            'messages',
            contains('correctOptionId'),
          ),
        ),
      );
    });
  });
}
