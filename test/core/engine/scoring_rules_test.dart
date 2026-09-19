/// Unit tests for the pluggable scoring rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  ScoringContext contextAt({
    required bool isCorrect,
    Duration elapsed = Duration.zero,
    Duration timeLimit = const Duration(seconds: 20),
    int rank = 0,
  }) => ScoringContext(
    isCorrect: isCorrect,
    elapsed: elapsed,
    timeLimit: timeLimit,
    rank: rank,
  );

  group('FixedPointsRule', () {
    test('awards the configured amount for a correct answer', () {
      const rule = FixedPointsRule(correctPoints: 12, wrongPoints: -3);

      expect(rule.evaluate(contextAt(isCorrect: true)).points, 12);
      expect(rule.evaluate(contextAt(isCorrect: false)).points, -3);
    });

    test('ignores how fast the answer arrived', () {
      const rule = FixedPointsRule(correctPoints: 12);

      final instant = rule.evaluate(contextAt(isCorrect: true));
      final late = rule.evaluate(
        contextAt(isCorrect: true, elapsed: const Duration(seconds: 19)),
      );

      expect(instant.points, late.points);
    });
  });

  group('SpeedBonusRule', () {
    const rule = SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10);

    test('grants the full bonus for an instant answer', () {
      expect(rule.evaluate(contextAt(isCorrect: true)).points, 20);
    });

    test('grants half the bonus at half the time limit', () {
      final delta = rule.evaluate(
        contextAt(isCorrect: true, elapsed: const Duration(seconds: 10)),
      );

      expect(delta.points, 15);
    });

    test('grants no bonus once the time limit elapsed', () {
      final delta = rule.evaluate(
        contextAt(isCorrect: true, elapsed: const Duration(seconds: 30)),
      );

      expect(delta.points, 10);
    });

    test('falls back to the wrong-answer amount', () {
      const penalised = SpeedBonusRule(wrongPoints: -2);

      expect(penalised.evaluate(contextAt(isCorrect: false)).points, -2);
    });
  });

  group('FirstBuzzerRule', () {
    const rule = FirstBuzzerRule(points: 15, penalty: -5, rankDecay: 5);

    test('pays the full amount to the fastest buzzer', () {
      expect(rule.evaluate(contextAt(isCorrect: true)).points, 15);
    });

    test('decays the reward for every failed attempt before it', () {
      expect(rule.evaluate(contextAt(isCorrect: true, rank: 1)).points, 10);
      expect(rule.evaluate(contextAt(isCorrect: true, rank: 2)).points, 5);
    });

    test('never pays a negative reward for a correct answer', () {
      expect(rule.evaluate(contextAt(isCorrect: true, rank: 9)).points, 0);
    });

    test('punishes a missed steal', () {
      expect(rule.evaluate(contextAt(isCorrect: false)).points, -5);
    });
  });

  group('serialization', () {
    test('round trips every rule variant', () {
      const rules = <ScoringRule>[
        FixedPointsRule(correctPoints: 7, wrongPoints: -1),
        SpeedBonusRule(basePoints: 5, maxSpeedBonus: 15, wrongPoints: -2),
        FirstBuzzerRule(points: 25, penalty: -10, rankDecay: 3),
      ];

      for (final rule in rules) {
        expect(ScoringRule.fromJson(rule.toJson()), rule);
      }
    });

    test('rejects an unknown rule tag', () {
      expect(
        () => ScoringRule.fromJson(const <String, Object?>{'type': 'nope'}),
        throwsA(isA<JsonContractException>()),
      );
    });
  });

  group('ScoreDelta', () {
    test('adds points and concatenates reasons', () {
      const a = ScoreDelta(5, reason: 'correct');
      const b = ScoreDelta(3, reason: 'speed');

      expect((a + b).points, 8);
      expect((a + b).reason, 'correct + speed');
    });
  });
}

