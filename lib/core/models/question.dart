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
import 'display_order.dart';
import 'estimation_format.dart';
import 'media_attachment.dart';
import 'question_hint.dart';
import '../engine/answer_evaluation.dart';
import '../engine/geo.dart';

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
    this.softTimeLimit = false,
    this.category,
    this.media = const [],
    this.solutionMedia = const [],
    this.adminNotes = '',
    this.hints = const [],
  });

  /// Stable identifier used by [StartRoundEvent] and the wire protocol.
  final String id;

  /// The text read out or displayed to the participants.
  final String prompt;

  /// Rule that converts a submission into points.
  final ScoringRule scoringRule;

  /// Budget for the whole round; [Duration.zero] means no time limit (the
  /// host ends the round). Supported from quiz schema 8 on.
  final Duration timeLimit;

  /// Whether the round runs against a clock at all.
  bool get hasTimeLimit => timeLimit > Duration.zero;
  final bool softTimeLimit;

  /// Optional grouping label such as `Geography`.
  final String? category;
  final List<MediaAttachment> media;
  final List<MediaAttachment> solutionMedia;
  final String adminNotes;

  /// Hints the host may show one after another while the question runs
  /// (quiz schema 13). Guests only receive the hints that are already shown;
  /// the others are concealed (`QuestionHint.concealed`).
  final List<QuestionHint> hints;

  /// [hints] without their content: only how many there are and their cost.
  List<QuestionHint> get concealedHints => [
    for (final hint in hints) hint.concealed(),
  ];

  bool accepts(AnswerSubmission answer);

  /// Whether input of this kind exists before it is sent and may count when
  /// the answers close (`AnswerDraft`).
  bool get supportsDrafts => false;

  /// Whether [content] may be taken over as an answer that was not sent.
  bool acceptsDraft(AnswerSubmission content) =>
      supportsDrafts && accepts(content);
  double accuracy(AnswerSubmission answer);

  /// Whether written answers require an explicit host verdict before scoring.
  bool get requiresManualGrading => false;

  String get solutionLabel;

  /// Violations of the content that do not concern the solution.
  List<String> get structureErrors => const [];

  /// Violations of the stored solution.
  List<String> get solutionErrors => const [];

  /// Every content violation of a question that is played with its solution.
  List<String> get contentErrors => [...structureErrors, ...solutionErrors];

  /// Canonical key of [answer]: two answers are the same answer exactly when
  /// their keys are equal. `null` when the kind has no finite, deterministic
  /// answer set (buzzer, free text, estimation) or [answer] is not accepted.
  ///
  /// Formats that compare answers with each other instead of with a solution
  /// (`SnowflakeFormat`) rely on it.
  String? uniquenessKey(AnswerSubmission answer) => null;

  /// Whether answers of this kind can be compared through [uniquenessKey].
  bool get supportsUniqueness => false;

  /// Returns a copy without the stored solution that keeps host notes, hints
  /// and solution media, for formats that are played without a solution.
  Question withoutSolution() => Question.fromJson({
    ...redacted().toJson(),
    'adminNotes': adminNotes,
    'solutionMedia': solutionMedia.map((m) => m.toJson()).toList(),
    'hints': hints.map((hint) => hint.toJson()).toList(),
  });

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

  /// The copy that is sent to guests, with the solution only on [reveal] and
  /// the content of the first [visibleHints] hints.
  Question forWire({
    required bool reveal,
    bool includeMediaData = false,
    int visibleHints = 0,
  }) {
    final visible = reveal ? this : redacted();
    return Question.fromJson({
      ...visible.toJson(),
      'adminNotes': '',
      'media': visible.media
          .map((m) => m.forWire(includeData: includeMediaData))
          .toList(),
      'solutionMedia': visible.solutionMedia
          .map((m) => m.forWire(includeData: includeMediaData))
          .toList(),
      'hints': [
        for (final (index, hint) in hints.indexed)
          index < visibleHints
              ? hint.forWire(includeMediaData: includeMediaData)
              : hint.concealed().toJson(),
      ],
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
    'location' => LocationQuestion.fromJson(json),
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
    'softTimeLimit': softTimeLimit,
    'category': category,
    'adminNotes': adminNotes,
    'media': media.map((m) => m.toJson()).toList(),
    'solutionMedia': solutionMedia.map((m) => m.toJson()).toList(),
    'scoringRule': scoringRule.toJson(),
    // Only written when set: files and saved games without hints stay equal.
    if (hints.isNotEmpty) 'hints': hints.map((hint) => hint.toJson()).toList(),
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
    this.correctOptionIds,
    this.allowMultipleAnswers = false,
    super.scoringRule = const SpeedBonusRule(),
    super.timeLimit = const Duration(seconds: 30),
    super.softTimeLimit,
    super.category,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
  });

  /// Restores the question from [json].
  factory MultipleChoiceQuestion.fromJson(JsonMap json) =>
      MultipleChoiceQuestion(
        id: json.readString('id'),
        prompt: json.readString('prompt'),
        options: json.readList('options', AnswerOption.fromJson),
        correctOptionId: json.readStringOrNull('correctOptionId'),
        correctOptionIds: json['correctOptionIds'] == null
            ? null
            : json.readStringList('correctOptionIds'),
        allowMultipleAnswers: json.readBool(
          'allowMultipleAnswers',
          orElse: false,
        ),
        scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
        timeLimit: json.readDurationMs('timeLimitMs'),
        softTimeLimit: json.readBool('softTimeLimit', orElse: false),
        category: json.readStringOrNull('category'),
        adminNotes: json.readStringOrNull('adminNotes') ?? '',
        media: readMedia(json, 'media'),
        solutionMedia: readMedia(json, 'solutionMedia'),
        hints: readHints(json),
      );

  static const String _type = 'multipleChoice';

  /// The selectable options, rendered in declaration order.
  final List<AnswerOption> options;

  /// Identifier of the correct entry in [options].
  ///
  /// `null` in player facing snapshots until the round is revealed.
  final String? correctOptionId;
  final List<String>? correctOptionIds;
  final bool allowMultipleAnswers;
  List<String> get solutionOptionIds => correctOptionIds ?? [?correctOptionId];

  /// A single choice is sent with the press.
  @override
  bool get supportsDrafts => allowMultipleAnswers;

  @override
  bool get hasSolution => correctOptionIds != null || correctOptionId != null;

  @override
  String get kindLabel => 'Multiple choice';

  /// Whether [optionId] is the correct answer.
  bool isCorrect(String optionId) => solutionOptionIds.contains(optionId);
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is MultipleChoiceAnswer &&
      answer.selectedOptionIds.isNotEmpty &&
      (allowMultipleAnswers || answer.selectedOptionIds.length == 1) &&
      answer.selectedOptionIds.toSet().length ==
          answer.selectedOptionIds.length &&
      answer.selectedOptionIds.every((id) => options.any((o) => o.id == id));
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is MultipleChoiceAnswer &&
          accepts(answer) &&
          isPermutation(answer.selectedOptionIds, solutionOptionIds)
      ? 1
      : 0;
  @override
  String get solutionLabel =>
      options.where((o) => isCorrect(o.id)).map((o) => o.label).join(' / ');

  @override
  bool get supportsUniqueness => true;

  @override
  String? uniquenessKey(AnswerSubmission answer) =>
      answer is MultipleChoiceAnswer && accepts(answer)
      ? ([...answer.selectedOptionIds]..sort()).join(_keySeparator)
      : null;

  @override
  MultipleChoiceQuestion redacted() => MultipleChoiceQuestion(
    id: id,
    prompt: prompt,
    options: options,
    allowMultipleAnswers: allowMultipleAnswers,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    category: category,
    media: media,
    hints: concealedHints,
  );

  @override
  JsonMap toJson() => {
    ...baseJson(_type),
    'options': options.map((option) => option.toJson()).toList(growable: false),
    'correctOptionId': correctOptionId,
    'correctOptionIds': correctOptionIds,
    'allowMultipleAnswers': allowMultipleAnswers,
  };

  @override
  List<Object?> get props => [
    id,
    prompt,
    options,
    correctOptionId,
    correctOptionIds,
    allowMultipleAnswers,
    scoringRule,
    timeLimit,
    softTimeLimit,
    category,
    media,
    solutionMedia,
    adminNotes,
    hints,
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
    this.hostEndsRound = false,
    this.retryLimit,
    super.scoringRule = const FirstBuzzerRule(),
    super.timeLimit = const Duration(seconds: 20),
    super.softTimeLimit,
    super.category,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
  });

  /// Restores the question from [json].
  factory BuzzerQuestion.fromJson(JsonMap json) => BuzzerQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    expectedAnswer: json.readStringOrNull('expectedAnswer'),
    lockOutOnMiss: json.readBool('lockOutOnMiss', orElse: true),
    hostEndsRound: json.readBool('hostEndsRound'),
    retryLimit: _readRetryLimit(json),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
  );

  static const String _type = 'buzzer';

  /// The answer the quizmaster expects to hear.
  ///
  /// `null` in player facing snapshots until the round is revealed.
  final String? expectedAnswer;

  /// Whether a player who buzzed and missed may buzz again this round.
  final bool lockOutOnMiss;

  final bool hostEndsRound;
  final int? retryLimit;

  static int? _readRetryLimit(JsonMap json) {
    final value = json['retryLimit'];
    if (value == null) return null;
    if (value is! num ||
        !value.isFinite ||
        value != value.toInt() ||
        value < 0) {
      throw const JsonContractException(
        'retryLimit must be a non-negative integer.',
      );
    }
    return value.toInt();
  }

  @override
  List<String> get contentErrors => retryLimit != null && retryLimit! < 0
      ? const ['Wiederholungen dürfen nicht negativ sein.']
      : const [];

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
    hostEndsRound: hostEndsRound,
    retryLimit: retryLimit,
    scoringRule: scoringRule,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    category: category,
    media: media,
    hints: concealedHints,
  );

  @override
  JsonMap toJson() => {
    ...baseJson(_type),
    'expectedAnswer': expectedAnswer,
    'lockOutOnMiss': lockOutOnMiss,
    'hostEndsRound': hostEndsRound,
    'retryLimit': retryLimit,
  };

  @override
  List<Object?> get props => [
    id,
    prompt,
    expectedAnswer,
    lockOutOnMiss,
    hostEndsRound,
    retryLimit,
    scoringRule,
    timeLimit,
    softTimeLimit,
    category,
    media,
    solutionMedia,
    adminNotes,
    hints,
  ];
}

final class ShortAnswerQuestion extends Question {
  const ShortAnswerQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.acceptedAnswers,
    this.maxEdits = 1,
    this.manualGrading = false,
  });
  final List<String>? acceptedAnswers;
  final int maxEdits;

  /// Whether the host judges each answer instead of applying fuzzy matching.
  final bool manualGrading;

  @override
  bool get requiresManualGrading => manualGrading;

  @override
  bool get supportsDrafts => true;
  factory ShortAnswerQuestion.fromJson(JsonMap json) => ShortAnswerQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
    acceptedAnswers: json['acceptedAnswers'] == null
        ? null
        : json.readStringList('acceptedAnswers'),
    maxEdits: json.readInt('maxEdits'),
    manualGrading: json.readBool('manualGrading'),
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
  List<String> get structureErrors => [
    if (maxEdits < 0 || maxEdits > 5)
      'Fehlertoleranz muss zwischen 0 und 5 liegen.',
  ];
  @override
  List<String> get solutionErrors => [
    if (acceptedAnswers == null ||
        acceptedAnswers!.isEmpty ||
        acceptedAnswers!.any((a) => a.trim().isEmpty))
      'Mindestens eine Textlösung angeben.',
  ];
  @override
  ShortAnswerQuestion redacted() => ShortAnswerQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
    maxEdits: maxEdits,
    manualGrading: manualGrading,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('shortAnswer'),
    'acceptedAnswers': acceptedAnswers,
    'maxEdits': maxEdits,
    'manualGrading': manualGrading,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
    manualGrading,
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
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.items = const [],
    this.correctOrder,
  });
  final List<AnswerOption> items;
  final List<String>? correctOrder;

  /// [items] as every device shows them: mixed per question, the same on
  /// all devices, never in the entered order (only public data decides, so
  /// host and guests agree).
  List<AnswerOption> get displayItems => displayOrder(items, id);

  factory OrderingQuestion.fromJson(JsonMap json) => OrderingQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
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
  bool get supportsDrafts => true;
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
  List<String> get structureErrors => optionErrors(items);

  @override
  List<String> get solutionErrors => [
    if (correctOrder == null ||
        !isPermutation(correctOrder!, items.map((i) => i.id).toList()))
      'Lösung muss jedes Element genau einmal enthalten.',
  ];

  @override
  bool get supportsUniqueness => true;

  @override
  String? uniquenessKey(AnswerSubmission answer) =>
      answer is OrderingAnswer && accepts(answer)
      ? answer.itemIds.join(_keySeparator)
      : null;
  @override
  OrderingQuestion redacted() => OrderingQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
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
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
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
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.leftItems = const [],
    this.rightItems = const [],
    this.correctPairs,
  });
  final List<AnswerOption> leftItems;
  final List<AnswerOption> rightItems;
  final Map<String, String>? correctPairs;

  /// [leftItems] as every device shows them, mixed per question.
  List<AnswerOption> get displayLeftItems => displayOrder(leftItems, '$id/a');

  /// [rightItems] as every device shows them, mixed per question. They never
  /// stand next to their left item as entered (the n-th right item beside
  /// the n-th left one); only public data decides, so host and guests agree.
  List<AnswerOption> get displayRightItems {
    final left = displayLeftItems;
    final aligned = leftItems.length == rightItems.length
        ? [for (final item in left) rightItems[leftItems.indexOf(item)]]
        : rightItems;
    return displayOrder(rightItems, '$id/b', avoid: aligned);
  }

  factory MatchingQuestion.fromJson(JsonMap json) => MatchingQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
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
  bool get supportsDrafts => true;

  /// The pairs so far count, also when some are still missing.
  @override
  bool acceptsDraft(AnswerSubmission content) =>
      content is MatchingAnswer &&
      content.pairs.isNotEmpty &&
      content.pairs.values.toSet().length == content.pairs.length &&
      content.pairs.keys.every((id) => leftItems.any((i) => i.id == id)) &&
      content.pairs.values.every((id) => rightItems.any((i) => i.id == id));
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is MatchingAnswer &&
      validPairs(answer.pairs, leftItems, rightItems);
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is MatchingAnswer &&
          correctPairs != null &&
          answer.pairs.length == correctPairs!.length &&
          correctPairs!.entries.every(
            (e) => switch (answer.pairs[e.key]) {
              final given? => _rightKey(given) == _rightKey(e.value),
              null => false,
            },
          )
      ? 1
      : 0;

  /// Right items with the same label are interchangeable: "pork" may exist
  /// twice, and either of them fits both pork dishes (since quiz schema 13).
  String _rightKey(String id) =>
      switch (rightItems.where((item) => item.id == id).firstOrNull) {
        final item? => item.label.trim().toLowerCase(),
        null => id,
      };
  @override
  String get solutionLabel => (correctPairs ?? {}).entries
      .map(
        (e) =>
            '${leftItems.where((i) => i.id == e.key).firstOrNull?.label ?? e.key} → ${rightItems.where((i) => i.id == e.value).firstOrNull?.label ?? e.value}',
      )
      .join('\n');
  @override
  List<String> get structureErrors => [
    ...optionErrors(leftItems),
    ...optionErrors(rightItems),
  ];

  @override
  List<String> get solutionErrors => [
    if (correctPairs == null ||
        !validPairs(correctPairs!, leftItems, rightItems))
      'Vollständige eindeutige Zuordnung angeben.',
  ];

  @override
  bool get supportsUniqueness => true;

  @override
  String? uniquenessKey(AnswerSubmission answer) =>
      answer is MatchingAnswer && accepts(answer)
      ? ([
          for (final pair in answer.pairs.entries)
            '${pair.key}$_keySeparator${_rightKey(pair.value)}',
        ]..sort()).join('$_keySeparator$_keySeparator')
      : null;
  @override
  MatchingQuestion redacted() => MatchingQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
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
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
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
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.correctValue,
    this.zeroScale = 1,
    this.unit = '',
    this.minAccepted,
    this.maxAccepted,
    this.toleranceOnly = false,
    this.valueFormat = EstimationValueFormat.number,
  });
  final double? correctValue;

  /// How values are entered and shown (quiz schema 18); the time formats
  /// store seconds. Public: players need it to enter their answer.
  final EstimationValueFormat valueFormat;

  /// Scoring mode "tolerance only" (quiz schema 17): an answer from
  /// [minAccepted] to [maxAccepted] earns the full points, every other none.
  /// Needs a tolerance; [zeroScale] has no effect then.
  final bool toleranceOnly;

  /// Whether [zeroScale] affects the score: only for the target 0 (where the
  /// relative deviation is undefined) and not in the mode [toleranceOnly].
  bool get usesZeroScale => !toleranceOnly && correctValue == 0;

  /// Optional tolerance (quiz schema 14): every answer from [minAccepted] to
  /// [maxAccepted] counts as fully correct. Both are set or none is. They
  /// belong to the solution and stay secret until the reveal.
  final double? minAccepted;
  final double? maxAccepted;

  bool get hasTolerance => minAccepted != null && maxAccepted != null;
  final double zeroScale;
  final String unit;
  factory EstimationQuestion.fromJson(JsonMap json) => EstimationQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
    correctValue: json['correctValue'] == null
        ? null
        : readFiniteDouble(json, 'correctValue'),
    zeroScale: readFiniteDouble(json, 'zeroScale'),
    unit: json.readString('unit'),
    minAccepted: json['minAccepted'] == null
        ? null
        : readFiniteDouble(json, 'minAccepted'),
    maxAccepted: json['maxAccepted'] == null
        ? null
        : readFiniteDouble(json, 'maxAccepted'),
    toleranceOnly: json.readBool('toleranceOnly', orElse: false),
    valueFormat: json['valueFormat'] == null
        ? EstimationValueFormat.number
        : EstimationValueFormat.fromJson(json['valueFormat']),
  );
  @override
  bool get hasSolution => correctValue != null;
  @override
  String get kindLabel => 'Schätzfrage';
  @override
  bool get supportsDrafts => true;
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is EstimationAnswer && answer.value.isFinite;
  @override
  double accuracy(AnswerSubmission answer) =>
      answer is EstimationAnswer && correctValue != null
      ? estimationAccuracyWithin(
          answer.value,
          correctValue!,
          zeroScale,
          min: minAccepted,
          max: maxAccepted,
          toleranceOnly: toleranceOnly,
        )
      : 0;
  @override
  String get solutionLabel => correctValue == null
      ? ''
      : hasTolerance
      ? '${valueLabel(correctValue!)} (${valueFormat.format(minAccepted!)} – ${valueLabel(maxAccepted!)})'
      : valueLabel(correctValue!);

  /// [value] in the format and with the unit of this question.
  String valueLabel(double value) =>
      '${valueFormat.format(value)} $unit'.trimRight();

  /// How far [value] is off the target, e.g. `+0:12`; `null` before the
  /// reveal, when the target is unknown.
  String? deviationLabel(double value) => correctValue == null
      ? null
      : '${valueFormat.formatDeviation(value - correctValue!)} $unit'
            .trimRight();
  @override
  List<String> get structureErrors => [
    if (!zeroScale.isFinite || zeroScale <= 0)
      'Skala für Zielwert 0 muss positiv sein.',
  ];
  @override
  List<String> get solutionErrors => [
    if (correctValue == null || !correctValue!.isFinite)
      'Endliche Zielzahl angeben.',
    if ((minAccepted == null) != (maxAccepted == null))
      'Für die Toleranz Unter- und Obergrenze angeben.'
    else if (toleranceOnly && !hasTolerance)
      'Für „Nur Toleranz“ Unter- und Obergrenze angeben.',
    if (hasTolerance && minAccepted! > maxAccepted!)
      'Die Untergrenze darf nicht über der Obergrenze liegen.'
    else if (hasTolerance &&
        correctValue != null &&
        (correctValue! < minAccepted! || correctValue! > maxAccepted!))
      'Der Zielwert muss im gültigen Bereich liegen.',
  ];
  @override
  EstimationQuestion redacted() => EstimationQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
    zeroScale: zeroScale,
    unit: unit,
    toleranceOnly: toleranceOnly,
    valueFormat: valueFormat,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('estimation'),
    'correctValue': correctValue,
    'zeroScale': zeroScale,
    'unit': unit,
    // Only written when set: questions without a tolerance stay equal.
    if (minAccepted != null) 'minAccepted': minAccepted,
    if (maxAccepted != null) 'maxAccepted': maxAccepted,
    if (toleranceOnly) 'toleranceOnly': true,
    if (valueFormat != EstimationValueFormat.number)
      'valueFormat': valueFormat.name,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
    correctValue,
    zeroScale,
    unit,
    minAccepted,
    maxAccepted,
    toleranceOnly,
    valueFormat,
  ];
}

final class TrueFalseQuestion extends Question {
  const TrueFalseQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.correctAnswer,
  });
  final bool? correctAnswer;
  factory TrueFalseQuestion.fromJson(JsonMap json) => TrueFalseQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
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
  List<String> get solutionErrors => [
    if (correctAnswer == null) 'Wahr oder Falsch als Lösung wählen.',
  ];

  @override
  bool get supportsUniqueness => true;

  @override
  String? uniquenessKey(AnswerSubmission answer) =>
      answer is TrueFalseAnswer ? '${answer.value}' : null;
  @override
  TrueFalseQuestion redacted() => TrueFalseQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
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
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
    correctAnswer,
  ];
}

/// A point on the earth.
final class GeoPoint extends Equatable {
  const GeoPoint(this.latitude, this.longitude);

  factory GeoPoint.fromJson(JsonMap json) => GeoPoint(
    readFiniteDouble(json, 'latitude'),
    readFiniteDouble(json, 'longitude'),
  );

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  JsonMap toJson() => {'latitude': latitude, 'longitude': longitude};

  /// Five decimals are about one metre.
  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  List<Object?> get props => [latitude, longitude];
}

/// "Where is this?": players mark a place on a map; the closer to [target],
/// the more points (quiz schema 16).
final class LocationQuestion extends Question {
  const LocationQuestion({
    required super.id,
    required super.prompt,
    super.category,
    super.timeLimit,
    super.softTimeLimit,
    super.scoringRule,
    super.media,
    super.solutionMedia,
    super.adminNotes,
    super.hints,
    this.target,
    this.targetLabel = '',
    this.fullPointsKm = 25,
    this.zeroPointsKm = 1000,
    this.startCenter = const GeoPoint(20, 0),
    this.startZoom = 1.5,
  });

  /// The place to find; `null` in snapshots until the reveal.
  final GeoPoint? target;

  /// Name of the place (from the search), part of the solution.
  final String targetLabel;

  /// Up to this distance a guess earns all points.
  final double fullPointsKm;

  /// From this distance on a guess earns nothing.
  final double zeroPointsKm;

  /// The view players start with; the world by default, so that it tells
  /// nothing.
  final GeoPoint startCenter;
  final double startZoom;

  factory LocationQuestion.fromJson(JsonMap json) => LocationQuestion(
    id: json.readString('id'),
    prompt: json.readString('prompt'),
    category: json.readStringOrNull('category'),
    adminNotes: json.readStringOrNull('adminNotes') ?? '',
    timeLimit: json.readDurationMs('timeLimitMs'),
    softTimeLimit: json.readBool('softTimeLimit', orElse: false),
    scoringRule: ScoringRule.fromJson(json.readObject('scoringRule')),
    media: readMedia(json, 'media'),
    solutionMedia: readMedia(json, 'solutionMedia'),
    hints: readHints(json),
    target: switch (json.readObjectOrNull('target')) {
      final value? => GeoPoint.fromJson(value),
      null => null,
    },
    targetLabel: json.readStringOrNull('targetLabel') ?? '',
    fullPointsKm: readFiniteDouble(json, 'fullPointsKm'),
    zeroPointsKm: readFiniteDouble(json, 'zeroPointsKm'),
    startCenter: GeoPoint.fromJson(json.readObject('startCenter')),
    startZoom: readFiniteDouble(json, 'startZoom'),
  );

  /// Distance of [answer] to the target in kilometres, if both are known.
  double? distanceOf(AnswerSubmission answer) => switch ((answer, target)) {
    (final LocationAnswer guess, final GeoPoint place) => distanceKm(
      guess.latitude,
      guess.longitude,
      place.latitude,
      place.longitude,
    ),
    _ => null,
  };

  @override
  bool get hasSolution => target != null;
  @override
  String get kindLabel => 'Ort auf der Karte';
  @override
  bool get supportsDrafts => true;
  @override
  bool accepts(AnswerSubmission answer) =>
      answer is LocationAnswer &&
      GeoPoint(answer.latitude, answer.longitude).isValid;
  @override
  double accuracy(AnswerSubmission answer) => switch (distanceOf(answer)) {
    final distance? when accepts(answer) => locationAccuracy(
      distance,
      fullPointsKm,
      zeroPointsKm,
    ),
    _ => 0,
  };
  @override
  String get solutionLabel => target == null
      ? ''
      : targetLabel.trim().isEmpty
      ? target!.label
      : '${targetLabel.trim()} (${target!.label})';
  @override
  List<String> get structureErrors => [
    if (!fullPointsKm.isFinite ||
        !zeroPointsKm.isFinite ||
        fullPointsKm < 0 ||
        zeroPointsKm <= fullPointsKm)
      '„Keine Punkte ab“ muss größer sein als „volle Punkte bis“.',
    if (zeroPointsKm > 20000) '„Keine Punkte ab“ darf höchstens 20000 km sein.',
    if (!startCenter.isValid ||
        !startZoom.isFinite ||
        startZoom < 1 ||
        startZoom > 18)
      'Ungültiger Startausschnitt der Karte.',
  ];
  @override
  List<String> get solutionErrors => [
    if (target == null || !target!.isValid) 'Gültigen Zielort angeben.',
  ];
  @override
  LocationQuestion redacted() => LocationQuestion(
    id: id,
    prompt: prompt,
    category: category,
    timeLimit: timeLimit,
    softTimeLimit: softTimeLimit,
    scoringRule: scoringRule,
    media: media,
    hints: concealedHints,
    fullPointsKm: fullPointsKm,
    zeroPointsKm: zeroPointsKm,
    startCenter: startCenter,
    startZoom: startZoom,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('location'),
    'target': target?.toJson(),
    if (targetLabel.isNotEmpty) 'targetLabel': targetLabel,
    'fullPointsKm': fullPointsKm,
    'zeroPointsKm': zeroPointsKm,
    'startCenter': startCenter.toJson(),
    'startZoom': startZoom,
  };
  @override
  List<Object?> get props => [
    id,
    prompt,
    category,
    timeLimit,
    softTimeLimit,
    scoringRule,
    media,
    solutionMedia,
    adminNotes,
    hints,
    target,
    targetLabel,
    fullPointsKm,
    zeroPointsKm,
    startCenter,
    startZoom,
  ];
}

/// Separates the parts of a `Question.uniquenessKey`; never part of an ID a
/// person types.
const _keySeparator = '\u001f';

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
