/// Pluggable point rules for the quiz engine.
///
/// Rules are a `sealed` hierarchy: adding a new rule forces every exhaustive
/// `switch` in the code base to be revisited, and scoring itself is resolved by
/// polymorphic dispatch rather than by branching on string identifiers
/// (architecture Rule 2).
library;

import 'package:equatable/equatable.dart';

import '../models/json.dart';

/// The immutable outcome of applying a [ScoringRule] to one submission.
final class ScoreDelta extends Equatable {
  /// Creates a delta worth [points], annotated with a human readable [reason].
  const ScoreDelta(this.points, {this.reason = ''});

  /// A delta that leaves the score untouched.
  static const ScoreDelta zero = ScoreDelta(0);

  /// Signed amount added to the participant's total.
  final int points;

  /// Short explanation rendered in the host's score feed.
  final String reason;

  /// Combines two deltas, concatenating their reasons.
  ScoreDelta operator +(ScoreDelta other) => ScoreDelta(
    points + other.points,
    reason: [reason, other.reason].where((part) => part.isNotEmpty).join(' + '),
  );

  @override
  List<Object?> get props => [points, reason];

  @override
  String toString() =>
      '${points >= 0 ? '+' : ''}$points${reason.isEmpty ? '' : ' ($reason)'}';
}

/// Everything a [ScoringRule] is allowed to look at.
///
/// The context deliberately contains only primitives: it decouples rules from
/// the question hierarchy so that a rule can be reused by any question kind.
final class ScoringContext extends Equatable {
  /// Creates a context for a single evaluated submission.
  const ScoringContext({
    required this.isCorrect,
    required this.elapsed,
    required this.timeLimit,
    this.rank = 0,
    this.attempt = 1,
  });

  /// Whether the submission was judged correct.
  final bool isCorrect;

  /// Time between the round start and the submission, on the host timeline.
  final Duration elapsed;

  /// Budget configured on the question.
  final Duration timeLimit;

  /// Zero based position among all competing submissions; `0` is the fastest.
  final int rank;

  /// One based attempt counter, used by rules that punish repeated guesses.
  final int attempt;

  /// Fraction of [timeLimit] that was still available, clamped to `[0, 1]`.
  double get remainingFraction {
    if (timeLimit <= Duration.zero) return 0;
    final remaining = timeLimit - elapsed;
    if (remaining <= Duration.zero) return 0;
    return (remaining.inMicroseconds / timeLimit.inMicroseconds).clamp(
      0.0,
      1.0,
    );
  }

  @override
  List<Object?> get props => [isCorrect, elapsed, timeLimit, rank, attempt];
}

/// Base type of every point rule.
sealed class ScoringRule extends Equatable {
  /// Const constructor so rules can be embedded in `const` question banks.
  const ScoringRule();

  /// Stable wire tag of this rule.
  String get typeId;

  /// Short label rendered on the host dashboard.
  String get label;

  /// Returns the points awarded for the submission described by [context].
  ScoreDelta evaluate(ScoringContext context);

  /// Serializes the rule including its configuration.
  JsonMap toJson();

  /// Restores a rule from [json].
  ///
  /// This is a deserialization boundary; it is the only place allowed to map
  /// wire tags onto Dart types.
  static ScoringRule fromJson(JsonMap json) =>
      switch (json.readString('type')) {
        FixedPointsRule._type => FixedPointsRule.fromJson(json),
        SpeedBonusRule._type => SpeedBonusRule.fromJson(json),
        FirstBuzzerRule._type => FirstBuzzerRule.fromJson(json),
        final unknown => throw JsonContractException(
          'Unknown scoring rule "$unknown".',
        ),
      };
}

/// Awards a constant amount, regardless of how fast the answer arrived.
final class FixedPointsRule extends ScoringRule {
  /// Creates a rule worth [correctPoints] on success.
  const FixedPointsRule({this.correctPoints = 10, this.wrongPoints = 0});

  /// Restores the rule from [json].
  factory FixedPointsRule.fromJson(JsonMap json) => FixedPointsRule(
    correctPoints: json.readInt('correctPoints'),
    wrongPoints: json.readInt('wrongPoints'),
  );

  static const String _type = 'fixed';

  /// Points granted for a correct submission.
  final int correctPoints;

  /// Points granted (usually negative or zero) for a wrong submission.
  final int wrongPoints;

  @override
  String get typeId => _type;

  @override
  String get label => 'Fixed $correctPoints pts';

  @override
  ScoreDelta evaluate(ScoringContext context) => context.isCorrect
      ? ScoreDelta(correctPoints, reason: 'correct')
      : ScoreDelta(wrongPoints, reason: 'wrong');

  @override
  JsonMap toJson() => {
    'type': _type,
    'correctPoints': correctPoints,
    'wrongPoints': wrongPoints,
  };

  @override
  List<Object?> get props => [correctPoints, wrongPoints];
}

/// Awards a base amount plus a bonus proportional to the remaining time.
final class SpeedBonusRule extends ScoringRule {
  /// Creates a rule worth `basePoints + maxSpeedBonus` for an instant answer.
  const SpeedBonusRule({
    this.basePoints = 10,
    this.maxSpeedBonus = 10,
    this.wrongPoints = 0,
  });

  /// Restores the rule from [json].
  factory SpeedBonusRule.fromJson(JsonMap json) => SpeedBonusRule(
    basePoints: json.readInt('basePoints'),
    maxSpeedBonus: json.readInt('maxSpeedBonus'),
    wrongPoints: json.readInt('wrongPoints'),
  );

  static const String _type = 'speedBonus';

  /// Guaranteed amount for any correct submission.
  final int basePoints;

  /// Additional amount granted for an answer given at `t = 0`.
  final int maxSpeedBonus;

  /// Points granted for a wrong submission.
  final int wrongPoints;

  @override
  String get typeId => _type;

  @override
  String get label => '$basePoints pts + up to $maxSpeedBonus speed';

  @override
  ScoreDelta evaluate(ScoringContext context) {
    if (!context.isCorrect) return ScoreDelta(wrongPoints, reason: 'wrong');
    final bonus = (maxSpeedBonus * context.remainingFraction).round();
    return ScoreDelta(
      basePoints + bonus,
      reason: bonus > 0 ? 'correct, +$bonus speed' : 'correct',
    );
  }

  @override
  JsonMap toJson() => {
    'type': _type,
    'basePoints': basePoints,
    'maxSpeedBonus': maxSpeedBonus,
    'wrongPoints': wrongPoints,
  };

  @override
  List<Object?> get props => [basePoints, maxSpeedBonus, wrongPoints];
}

/// Rewards the latency adjusted buzzer ranking and punishes a missed steal.
final class FirstBuzzerRule extends ScoringRule {
  /// Creates a buzzer rule worth [points] for the fastest correct answer.
  const FirstBuzzerRule({
    this.points = 15,
    this.penalty = -5,
    this.rankDecay = 5,
  });

  /// Restores the rule from [json].
  factory FirstBuzzerRule.fromJson(JsonMap json) => FirstBuzzerRule(
    points: json.readInt('points'),
    penalty: json.readInt('penalty'),
    rankDecay: json.readInt('rankDecay'),
  );

  static const String _type = 'firstBuzzer';

  /// Amount granted to the fastest buzzer (`rank == 0`).
  final int points;

  /// Amount subtracted when a player buzzes but fails to answer.
  final int penalty;

  /// Amount removed per rank for players who take over after a miss.
  final int rankDecay;

  @override
  String get typeId => _type;

  @override
  String get label => '$points pts, $penalty on miss';

  @override
  ScoreDelta evaluate(ScoringContext context) {
    if (!context.isCorrect) {
      return ScoreDelta(penalty, reason: 'buzzed but missed');
    }
    final awarded = (points - rankDecay * context.rank)
        .clamp(0, points)
        .toInt();
    return ScoreDelta(
      awarded,
      reason: context.rank == 0
          ? 'fastest buzzer'
          : 'buzzer #${context.rank + 1}',
    );
  }

  @override
  JsonMap toJson() => {
    'type': _type,
    'points': points,
    'penalty': penalty,
    'rankDecay': rankDecay,
  };

  @override
  List<Object?> get props => [points, penalty, rankDecay];
}

ScoreDelta evaluateAccuracy(
  ScoringRule rule,
  ScoringContext context,
  double accuracy,
) {
  final delta = rule.evaluate(context);
  return accuracy > 0 && accuracy < 1
      ? ScoreDelta(
          (delta.points * accuracy).round(),
          reason: '${(accuracy * 100).round()}% accuracy',
        )
      : delta;
}

// The stake has already been deducted when betting. Only a fully correct
// answer returns twice the stake; a miss or no answer returns nothing.
int pokerChipPayout({required int wager, required bool isCorrect}) =>
    isCorrect ? wager * 2 : 0;
