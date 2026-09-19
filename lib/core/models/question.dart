/// The polymorphic question hierarchy.
///
/// [Question] is `sealed`, therefore the analyzer rejects every `switch` that
/// forgets a variant. Adding `EstimationQuestion` or `OrderingQuestion` later
/// is a compile time guided refactor instead of a runtime surprise.
library;

import 'package:equatable/equatable.dart';

import '../engine/scoring_rules.dart';
import 'json.dart';

/// A single selectable option of a [MultipleChoiceQuestion].
final class AnswerOption extends Equatable {
  /// Creates an option identified by [id] and rendered as [label].
  const AnswerOption({required this.id, required this.label});

  /// Restores an option from [json].
  factory AnswerOption.fromJson(JsonMap json) => AnswerOption(
    id: json.readString('id'),
    label: json.readString('label'),
  );

  /// Stable identifier, unique within its question.
  final String id;

  /// Text shown to the player.
  final String label;

  /// Serializes the option.
  JsonMap toJson() => {'id': id, 'label': label};

  @override
  List<Object?> get props => [id, label];
}

/// Base type of every quiz question.
sealed class Question extends Equatable {
  /// Creates the shared question metadata.
  const Question({
    required this.id,
    required this.prompt,
    this.scoringRule = const FixedPointsRule(),
    this.timeLimit = const Duration(seconds: 30),
    this.category,
  });

  /// Stable identifier used by [StartRoundEvent] and the wire protocol.
  final String id;

  /// The text read out or displayed to the participants.
  final String prompt;

  /// Rule that converts a submission into points.
  final ScoringRule scoringRule;

  /// Budget for the whole round.
  final Duration timeLimit;

  /// Optional grouping label such as `Geography`.
  final String? category;

  /// Whether this instance still carries the solution.
  ///
  /// Player facing snapshots are redacted, so the solution is `null` there
  /// until the host reveals the round.
  bool get hasSolution;

  /// Short type label rendered on the host dashboard.
  String get kindLabel;

  /// Returns a copy without the solution, safe to broadcast to players.
  Question redacted();

  /// Serializes the question **including** its solution.
  JsonMap toJson();

  /// Restores a question from [json].
  ///
  /// Deserialization is the one legitimate place to map wire tags onto Dart
  /// types; downstream code pattern matches on the resulting subclass.
  static Question fromJson(JsonMap json) => switch (json.readString('type')) {
    MultipleChoiceQuestion._type => MultipleChoiceQuestion.fromJson(json),
    BuzzerQuestion._type => BuzzerQuestion.fromJson(json),
    final unknown => throw JsonContractException(
      'Unknown question type "$unknown".',
    ),
  };

  /// Serializes the fields shared by every variant.
  JsonMap baseJson(String type) => {
    'type': type,
    'id': id,
    'prompt': prompt,
    'timeLimitMs': timeLimit.inMilliseconds,
    'category': category,
    'scoringRule': scoringRule.toJson(),
  };
}

/// A question answered by picking exactly one of [options].
final class MultipleChoiceQuestion extends Question {
  /// Creates a multiple choice question.
  const MultipleChoiceQuestion({
    required super.id,
    required super.prompt,
    required this.options,
    this.correctOptionId,
    super.scoringRule = const SpeedBonusRule(),
    super.timeLimit = const Duration(seconds: 30),
    super.category,
  });

  /// Restores the question from [json].
  factory MultipleChoiceQuestion.fromJson(JsonMap json) =>
      MultipleChoiceQuestion(
        id: json.readString('id'),
        prompt: json.readString('prompt'),
        options: json.readList('options', AnswerOption.fromJson),
        correctOptionId: json.readStringOrNull('correctOptionId'),
        scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
        timeLimit: json.readDurationMs('timeLimitMs'),
        category: json.readStringOrNull('category'),
      );

  static const String _type = 'multipleChoice';

  /// The selectable options, rendered in declaration order.
  final List<AnswerOption> options;

  /// Identifier of the correct entry in [options].
  ///
  /// `null` in player facing snapshots until the round is revealed.
  final String? correctOptionId;

  @override
  bool get hasSolution => correctOptionId != null;

  @override
  String get kindLabel => 'Multiple choice';

  /// Whether [optionId] is the correct answer.
  bool isCorrect(String optionId) => correctOptionId == optionId;

  @override
  MultipleChoiceQuestion redacted() => MultipleChoiceQuestion(
    id: id,
    prompt: prompt,
    options: options,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    category: category,
  );

  @override
  JsonMap toJson() => {
    ...baseJson(_type),
    'options': options.map((option) => option.toJson()).toList(growable: false),
    'correctOptionId': correctOptionId,
  };

  @override
  List<Object?> get props => [
    id,
    prompt,
    options,
    correctOptionId,
    scoringRule,
    timeLimit,
    category,
  ];
}

/// A question answered verbally after hitting the buzzer.
///
/// The winner is decided by the latency adjusted press timestamp, never by the
/// order in which the packets happened to reach the host (architecture Rule 3).
final class BuzzerQuestion extends Question {
  /// Creates a buzzer question.
  const BuzzerQuestion({
    required super.id,
    required super.prompt,
    this.expectedAnswer,
    this.lockOutOnMiss = true,
    super.scoringRule = const FirstBuzzerRule(),
    super.timeLimit = const Duration(seconds: 20),
    super.category,
  });

  /// Restores the question from [json].
  factory BuzzerQuestion.fromJson(JsonMap json) => BuzzerQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    expectedAnswer: json.readStringOrNull('expectedAnswer'),
    lockOutOnMiss: json.readBool('lockOutOnMiss', orElse: true),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    timeLimit: json.readDurationMs('timeLimitMs'),
    category: json.readStringOrNull('category'),
  );

  static const String _type = 'buzzer';

  /// The answer the quizmaster expects to hear.
  ///
  /// `null` in player facing snapshots until the round is revealed.
  final String? expectedAnswer;

  /// Whether a player who buzzed and missed may buzz again this round.
  final bool lockOutOnMiss;

  @override
  bool get hasSolution => expectedAnswer != null;

  @override
  String get kindLabel => 'Fast buzzer';

  @override
  BuzzerQuestion redacted() => BuzzerQuestion(
    id: id,
    prompt: prompt,
    lockOutOnMiss: lockOutOnMiss,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    category: category,
  );

  @override
  JsonMap toJson() => {
    ...baseJson(_type),
    'expectedAnswer': expectedAnswer,
    'lockOutOnMiss': lockOutOnMiss,
  };

  @override
  List<Object?> get props => [
    id,
    prompt,
    expectedAnswer,
    lockOutOnMiss,
    scoringRule,
    timeLimit,
    category,
  ];
}

