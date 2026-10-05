/// The polymorphic question hierarchy.
///
/// [Question] is `sealed`, therefore the analyzer rejects every `switch` that
/// forgets a variant. Adding `EstimationQuestion` or `OrderingQuestion` later
/// is a compile time guided refactor instead of a runtime surprise.
library;

import 'package:equatable/equatable.dart';

import '../engine/scoring_rules.dart';
import 'json.dart';
import 'answer.dart';
import 'media_attachment.dart';
import '../engine/answer_evaluation.dart';

/// A single selectable option of a [MultipleChoiceQuestion].
final class AnswerOption extends Equatable {
  /// Creates an option identified by [id] and rendered as [label].
  const AnswerOption({required this.id, required this.label});

  /// Restores an option from [json].
  factory AnswerOption.fromJson(JsonMap json) =>
      AnswerOption(id: json.readString('id'), label: json.readString('label'));

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
    this.media = const [],
    this.solutionMedia = const [],
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
  final List<MediaAttachment> media;
  final List<MediaAttachment> solutionMedia;
  bool accepts(AnswerSubmission answer);
  double accuracy(AnswerSubmission answer);
  String get solutionLabel;
  List<String> get contentErrors => const [];

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

  Question forWire({required bool reveal}) {
    final visible = reveal ? this : redacted();
    return Question.fromJson({
      ...visible.toJson(),
      'media': visible.media.map((m) => m.forWire()).toList(),
      'solutionMedia': visible.solutionMedia.map((m) => m.forWire()).toList(),
    });
  }

  /// Restores a question from [json].
  ///
  /// Deserialization is the one legitimate place to map wire tags onto Dart
  /// types; downstream code pattern matches on the resulting subclass.
  static Question fromJson(JsonMap json) => switch (json.readString('type')) {
    MultipleChoiceQuestion._type => MultipleChoiceQuestion.fromJson(json),
    BuzzerQuestion._type => BuzzerQuestion.fromJson(json),
    'shortAnswer' => ShortAnswerQuestion.fromJson(json),
    'ordering' => OrderingQuestion.fromJson(json),
    'matching' => MatchingQuestion.fromJson(json),
    'estimation' => EstimationQuestion.fromJson(json),
    'trueFalse' => TrueFalseQuestion.fromJson(json),
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
    'media': media.map((m) => m.toJson()).toList(),
    'solutionMedia': solutionMedia.map((m) => m.toJson()).toList(),
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
    super.media,
    super.solutionMedia,
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
        media: readMedia(json, 'media'),
        solutionMedia: readMedia(json, 'solutionMedia'),
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
  bool accepts(AnswerSubmission answer) =>
      answer is MultipleChoiceAnswer &&
      options.any((o) => o.id == answer.optionId);
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is MultipleChoiceAnswer && isCorrect(answer.optionId) ? 1 : 0;
  @override
  String get solutionLabel =>
      options.where((o) => o.id == correctOptionId).firstOrNull?.label ?? '';

  @override
  MultipleChoiceQuestion redacted() => MultipleChoiceQuestion(
    id: id,
    prompt: prompt,
    options: options,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    category: category,
    media: media,
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
    media,
    solutionMedia,
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
    super.media,
    super.solutionMedia,
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
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
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
  bool accepts(AnswerSubmission answer) => answer is BuzzerPress;
  @override
  double accuracy(AnswerSubmission answer) => 0;
  @override
  String get solutionLabel => expectedAnswer ?? '';

  @override
  BuzzerQuestion redacted() => BuzzerQuestion(
    id: id,
    prompt: prompt,
    lockOutOnMiss: lockOutOnMiss,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    category: category,
    media: media,
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
    media,
    solutionMedia,
  ];
}

final class ShortAnswerQuestion extends Question {
  const ShortAnswerQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    this.acceptedAnswers,
    this.maxEdits = 1,
  });
  final List<String>? acceptedAnswers;
  final int maxEdits;
  factory ShortAnswerQuestion.fromJson(JsonMap json) => ShortAnswerQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    timeLimit: json.readDurationMs('timeLimitMs'),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    acceptedAnswers: json['acceptedAnswers'] == null
        ? null
        : json.readStringList('acceptedAnswers'),
    maxEdits: json.readInt('maxEdits'),
  );
  @override
  bool get hasSolution => acceptedAnswers != null;
  @override
  String get kindLabel => 'Freitext';
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is ShortAnswer &&
      answer.text.trim().isNotEmpty &&
      answer.text.length <= 2000;
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is ShortAnswer &&
          (acceptedAnswers ?? []).any(
            (a) => fuzzyEquals(answer.text, a, maxEdits),
          )
      ? 1
      : 0;
  @override
  String get solutionLabel => acceptedAnswers?.join(' / ') ?? '';
  @override
  List<String> get contentErrors => [
    if (acceptedAnswers == null ||
        acceptedAnswers!.isEmpty ||
        acceptedAnswers!.any((a) => a.trim().isEmpty))
      'Mindestens eine Textlösung angeben.',
    if (maxEdits < 0 || maxEdits > 5)
      'Fehlertoleranz muss zwischen 0 und 5 liegen.',
  ];
  @override
  ShortAnswerQuestion redacted() => ShortAnswerQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    scoringRule: scoringRule,
    media: media,
    maxEdits: maxEdits,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('shortAnswer'),
    'acceptedAnswers': acceptedAnswers,
    'maxEdits': maxEdits,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    scoringRule,
    media,
    solutionMedia,
    acceptedAnswers,
    maxEdits,
  ];
}

final class OrderingQuestion extends Question {
  const OrderingQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    this.items = const [],
    this.correctOrder,
  });
  final List<AnswerOption> items;
  final List<String>? correctOrder;
  factory OrderingQuestion.fromJson(JsonMap json) => OrderingQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    timeLimit: json.readDurationMs('timeLimitMs'),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    items: json.readList('items', AnswerOption.fromJson),
    correctOrder: json['correctOrder'] == null
        ? null
        : json.readStringList('correctOrder'),
  );
  @override
  bool get hasSolution => correctOrder != null;
  @override
  String get kindLabel => 'Reihenfolge';
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is OrderingAnswer &&
      isPermutation(answer.itemIds, items.map((i) => i.id).toList());
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is OrderingAnswer &&
          correctOrder != null &&
          sameOrder(answer.itemIds, correctOrder!)
      ? 1
      : 0;
  @override
  String get solutionLabel => (correctOrder ?? [])
      .map((id) => items.where((i) => i.id == id).firstOrNull?.label ?? id)
      .join(' → ');
  @override
  List<String> get contentErrors => [
    ...optionErrors(items),
    if (correctOrder == null ||
        !isPermutation(correctOrder!, items.map((i) => i.id).toList()))
      'Lösung muss jedes Element genau einmal enthalten.',
  ];
  @override
  OrderingQuestion redacted() => OrderingQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    scoringRule: scoringRule,
    media: media,
    items: items,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('ordering'),
    'items': items.map((i) => i.toJson()).toList(),
    'correctOrder': correctOrder,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    scoringRule,
    media,
    solutionMedia,
    items,
    correctOrder,
  ];
}

final class MatchingQuestion extends Question {
  const MatchingQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    this.leftItems = const [],
    this.rightItems = const [],
    this.correctPairs,
  });
  final List<AnswerOption> leftItems;
  final List<AnswerOption> rightItems;
  final Map<String, String>? correctPairs;
  factory MatchingQuestion.fromJson(JsonMap json) => MatchingQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    timeLimit: json.readDurationMs('timeLimitMs'),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    leftItems: json.readList('leftItems', AnswerOption.fromJson),
    rightItems: json.readList('rightItems', AnswerOption.fromJson),
    correctPairs: json['correctPairs'] == null
        ? null
        : readStringMap(json, 'correctPairs'),
  );
  @override
  bool get hasSolution => correctPairs != null;
  @override
  String get kindLabel => 'Zuordnung';
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is MatchingAnswer &&
      validPairs(answer.pairs, leftItems, rightItems);
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is MatchingAnswer &&
          correctPairs != null &&
          answer.pairs.length == correctPairs!.length &&
          correctPairs!.entries.every((e) => answer.pairs[e.key] == e.value)
      ? 1
      : 0;
  @override
  String get solutionLabel => (correctPairs ?? {}).entries
      .map(
        (e) =>
            '${leftItems.where((i) => i.id == e.key).firstOrNull?.label ?? e.key} → ${rightItems.where((i) => i.id == e.value).firstOrNull?.label ?? e.value}',
      )
      .join('\n');
  @override
  List<String> get contentErrors => [
    ...optionErrors(leftItems),
    ...optionErrors(rightItems),
    if (correctPairs == null ||
        !validPairs(correctPairs!, leftItems, rightItems))
      'Vollständige eindeutige Zuordnung angeben.',
  ];
  @override
  MatchingQuestion redacted() => MatchingQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    scoringRule: scoringRule,
    media: media,
    leftItems: leftItems,
    rightItems: rightItems,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('matching'),
    'leftItems': leftItems.map((i) => i.toJson()).toList(),
    'rightItems': rightItems.map((i) => i.toJson()).toList(),
    'correctPairs': correctPairs,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    scoringRule,
    media,
    solutionMedia,
    leftItems,
    rightItems,
    correctPairs,
  ];
}

final class EstimationQuestion extends Question {
  const EstimationQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    this.correctValue,
    this.zeroScale = 1,
    this.unit = '',
  });
  final double? correctValue;
  final double zeroScale;
  final String unit;
  factory EstimationQuestion.fromJson(JsonMap json) => EstimationQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    timeLimit: json.readDurationMs('timeLimitMs'),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    correctValue: json['correctValue'] == null
        ? null
        : readFiniteDouble(json, 'correctValue'),
    zeroScale: readFiniteDouble(json, 'zeroScale'),
    unit: json.readString('unit'),
  );
  @override
  bool get hasSolution => correctValue != null;
  @override
  String get kindLabel => 'Schätzfrage';
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is EstimationAnswer && answer.value.isFinite;
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is EstimationAnswer && correctValue != null
      ? estimationAccuracy(answer.value, correctValue!, zeroScale)
      : 0;
  @override
  String get solutionLabel => correctValue == null ? '' : '$correctValue $unit';
  @override
  List<String> get contentErrors => [
    if (correctValue == null || !correctValue!.isFinite)
      'Endliche Zielzahl angeben.',
    if (!zeroScale.isFinite || zeroScale <= 0)
      'Skala für Zielwert 0 muss positiv sein.',
  ];
  @override
  EstimationQuestion redacted() => EstimationQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    scoringRule: scoringRule,
    media: media,
    zeroScale: zeroScale,
    unit: unit,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('estimation'),
    'correctValue': correctValue,
    'zeroScale': zeroScale,
    'unit': unit,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    scoringRule,
    media,
    solutionMedia,
    correctValue,
    zeroScale,
    unit,
  ];
}

final class TrueFalseQuestion extends Question {
  const TrueFalseQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    this.correctAnswer,
  });
  final bool? correctAnswer;
  factory TrueFalseQuestion.fromJson(JsonMap json) => TrueFalseQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    timeLimit: json.readDurationMs('timeLimitMs'),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    correctAnswer: json['correctAnswer'] == null
        ? null
        : json.readBool('correctAnswer'),
  );
  @override
  bool get hasSolution => correctAnswer != null;
  @override
  String get kindLabel => 'Wahr / Falsch';
  @override
  bool accepts(AnswerSubmission answer) => answer is TrueFalseAnswer;
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is TrueFalseAnswer && answer.value == correctAnswer ? 1 : 0;
  @override
  String get solutionLabel => correctAnswer == null
      ? ''
      : correctAnswer!
      ? 'Wahr'
      : 'Falsch';
  @override
  List<String> get contentErrors => [
    if (correctAnswer == null) 'Wahr oder Falsch als Lösung wählen.',
  ];
  @override
  TrueFalseQuestion redacted() => TrueFalseQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    scoringRule: scoringRule,
    media: media,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('trueFalse'),
    'correctAnswer': correctAnswer,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    scoringRule,
    media,
    solutionMedia,
    correctAnswer,
  ];
}

bool sameOrder(List<String> a, List<String> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);
bool isPermutation(List<String> a, List<String> b) =>
    a.length == b.length &&
    a.toSet().length == a.length &&
    a.toSet().containsAll(b);
bool validPairs(
  Map<String, String> pairs,
  List<AnswerOption> left,
  List<AnswerOption> right,
) =>
    isPermutation(pairs.keys.toList(), left.map((i) => i.id).toList()) &&
    isPermutation(pairs.values.toList(), right.map((i) => i.id).toList());
List<String> optionErrors(List<AnswerOption> items) => [
  if (items.length < 2 || items.length > 50)
    'Zwischen 2 und 50 Elemente angeben.',
  if (items.any((i) => i.id.trim().isEmpty || i.label.trim().isEmpty) ||
      items.map((i) => i.id).toSet().length != items.length)
    'Elemente brauchen eindeutige IDs und Beschriftungen.',
];
