import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';
import 'package:quizmo/core/simulation/simulation_clock.dart';

const simulationQuestions = <Question>[
  MultipleChoiceQuestion(
    id: 'choice',
    prompt: 'Choice',
    options: [
      AnswerOption(id: 'a', label: 'A'),
      AnswerOption(id: 'b', label: 'B'),
    ],
    correctOptionId: 'a',
  ),
  MultipleChoiceQuestion(
    id: 'multi',
    prompt: 'All correct',
    allowMultipleAnswers: true,
    options: [
      AnswerOption(id: 'a', label: 'A'),
      AnswerOption(id: 'b', label: 'B'),
    ],
    correctOptionIds: ['a', 'b'],
  ),
  ShortAnswerQuestion(
    id: 'text',
    prompt: 'Text',
    acceptedAnswers: ['x', 'xxx'],
    maxEdits: 5,
  ),
  OrderingQuestion(
    id: 'order',
    prompt: 'Order',
    items: [
      AnswerOption(id: 'a', label: 'A'),
      AnswerOption(id: 'b', label: 'B'),
    ],
    correctOrder: ['a', 'b'],
  ),
  MatchingQuestion(
    id: 'match',
    prompt: 'Match',
    leftItems: [
      AnswerOption(id: 'a', label: 'A'),
      AnswerOption(id: 'b', label: 'B'),
    ],
    rightItems: [
      AnswerOption(id: 'c', label: 'C'),
      AnswerOption(id: 'd', label: 'D'),
    ],
    correctPairs: {'a': 'c', 'b': 'd'},
  ),
  EstimationQuestion(id: 'estimate', prompt: 'Estimate', correctValue: -100),
  EstimationQuestion(
    id: 'zero',
    prompt: 'Zero',
    correctValue: 0,
    zeroScale: 20,
  ),
  TrueFalseQuestion(id: 'bool', prompt: 'Bool', correctAnswer: true),
  BuzzerQuestion(id: 'buzz', prompt: 'Buzz', expectedAnswer: 'Answer'),
];

void main() {
  test(
    'every question has valid fully right and zero-credit wrong answers',
    () {
      for (final question in simulationQuestions) {
        for (final correct in [false, true]) {
          final answer = botAnswer(
            question,
            playerId: 'bot',
            timestamp: 123,
            correct: correct,
          );
          expect(question.accepts(answer), isTrue, reason: question.id);
          expect(answer.hostTimestampMicros, 123);
          if (question is! BuzzerQuestion) {
            expect(
              question.accuracy(answer),
              correct ? 1 : 0,
              reason: question.id,
            );
          }
        }
      }
    },
  );

  test(
    'probability boundaries, fixed seed distribution and inclusive delays',
    () {
      final random = Random(53);
      final settings = BotSettings(
        accuracy: 0.37,
        minDelayMs: 2,
        maxDelayMs: 4,
      );
      var hits = 0;
      final delays = <int>{};
      for (var i = 0; i < 10000; i++) {
        if (settings.succeeds(random)) hits++;
        delays.add(settings.delay(random).inMilliseconds);
        expect(BotSettings(accuracy: 0).succeeds(random), isFalse);
        expect(BotSettings(accuracy: 1).succeeds(random), isTrue);
      }
      expect(hits, inInclusiveRange(3400, 4000));
      expect(delays, {2, 3, 4});
      expect(
        BotSettings(minDelayMs: 0, maxDelayMs: 0).delay(random),
        Duration.zero,
      );
      for (final accuracy in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(() => BotSettings(accuracy: accuracy), throwsArgumentError);
      }
      expect(() => BotSettings(minDelayMs: -1), throwsArgumentError);
      expect(
        () => BotSettings(minDelayMs: 5, maxDelayMs: 4),
        throwsArgumentError,
      );
    },
  );

  test(
    'virtual timers run in stable time order, including nested engine work',
    () async {
      final clock = SimulationClock();
      final events = <int>[];
      clock.schedule(
        const Duration(milliseconds: 3),
        () => events.add(clock.nowMicros),
      );
      final cancelled = clock.schedule(Duration.zero, () => fail('cancelled'));
      cancelled.cancel();
      clock.schedule(const Duration(milliseconds: 1), () {
        events.add(clock.nowMicros);
        clock.schedule(Duration.zero, () => events.add(clock.nowMicros));
      });
      await clock.advance(const Duration(milliseconds: 5));
      expect(events, [1000, 1000, 3000]);
      expect(clock.nowMicros, 5000);
      expect(clock.pendingCount, 0);
    },
  );
}
