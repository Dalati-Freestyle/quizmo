/// State of the round that is currently on stage.
library;

import 'package:equatable/equatable.dart';

import 'answer.dart';
import 'json.dart';
import '../engine/scoring_rules.dart';
import 'question.dart';
import 'question_hint.dart';
import 'snowflake.dart';

const Object _unset = Object();

/// Lifecycle of a single round.
enum RoundStatus {
  /// No question is on stage.
  idle,

  /// The question is visible and player input is accepted.
  acceptingAnswers,

  /// Input is closed while the host judges answers or prepares the reveal.
  locked,

  /// The solution is public and the points are booked.
  revealed;

  /// Whether new submissions are still accepted.
  bool get acceptsInput => this == RoundStatus.acceptingAnswers;

  /// Restores a status from its wire name.
  static RoundStatus fromName(String name) => RoundStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => throw JsonContractException('Unknown round status "$name".'),
  );
}

/// Everything that belongs to the question currently on stage.
final class RoundState extends Equatable {
  /// Creates a round state.
  const RoundState({
    this.question,
    this.status = RoundStatus.idle,
    this.startedAtHostMicros,
    this.buzzerQueue = const [],
    this.answers = const {},
    this.activePlayerId,
    this.lockedOutPlayerIds = const {},
    this.resolvedAttempts = 0,
    this.buzzerAnswerCorrect = false,
    this.buzzerOpenForAll = false,
    this.buzzerVerdicts = const {},
    this.answerVerdicts = const {},
    this.recoverySoftTimer = false,
    this.timerRestartedAtHostMicros,
    this.acceptedElapsedMicros = const {},
    this.snowflake,
    this.hiddenAnswerCount = 0,
    this.verbal = false,
    this.hintTimesMicros = const [],
  });

  /// Restores a round from [json].
  factory RoundState.fromJson(JsonMap json) => RoundState(
    hiddenAnswerCount: json.readIntOrNull('hiddenAnswerCount') ?? 0,
    verbal: json.readBool('verbal', orElse: false),
    hintTimesMicros: json['hintTimesMicros'] == null
        ? const []
        : json.readIntList('hintTimesMicros'),
    snowflake: switch (json.readStringOrNull('snowflake')) {
      final name? => SnowflakeScoring.fromName(name),
      null => null,
    },
    recoverySoftTimer: json.readBool('recoverySoftTimer'),
    timerRestartedAtHostMicros: json.readIntOrNull(
      'timerRestartedAtHostMicros',
    ),
    acceptedElapsedMicros: json['acceptedElapsedMicros'] == null
        ? const {}
        : json.readIntMap('acceptedElapsedMicros'),
    question: switch (json.readObjectOrNull('question')) {
      final JsonMap value => Question.fromJson(value),
      null => null,
    },
    status: RoundStatus.fromName(json.readString('status')),
    startedAtHostMicros: json.readIntOrNull('startedAtHostMicros'),
    buzzerQueue: json.readList('buzzerQueue', BuzzerPress.fromJson),
    answers: json.readMap('answers', AnswerSubmission.fromJson),
    activePlayerId: json.readStringOrNull('activePlayerId'),
    lockedOutPlayerIds: json.readStringList('lockedOutPlayerIds').toSet(),
    resolvedAttempts: json.readInt('resolvedAttempts'),
    buzzerAnswerCorrect: json.readBool('buzzerAnswerCorrect'),
    buzzerOpenForAll: json.readBool('buzzerOpenForAll'),
    buzzerVerdicts: json['buzzerVerdicts'] == null
        ? const {}
        : json.readIntMap('buzzerVerdicts'),
    answerVerdicts: json['answerVerdicts'] == null
        ? const {}
        : json.readIntMap('answerVerdicts'),
  );

  /// The neutral "nothing on stage" round.
  static const RoundState idle = RoundState();

  /// The question on stage, redacted in player facing snapshots.
  final Question? question;

  /// Current lifecycle position.
  final RoundStatus status;

  /// Instant the round was opened, on the host timeline.
  final int? startedAtHostMicros;

  /// Buzzer presses sorted ascending by `hostTimestampMicros`.
  ///
  /// The sort key is the latency adjusted timestamp, so a press that arrived
  /// late because of a slow link can still win the race.
  final List<BuzzerPress> buzzerQueue;

  /// Multiple choice submissions keyed by player id; the first one counts.
  final Map<String, AnswerSubmission> answers;

  /// Player that currently holds the floor, if any.
  final String? activePlayerId;

  /// Players that already buzzed and missed this round.
  final Set<String> lockedOutPlayerIds;

  /// Number of buzzer answers the quizmaster already judged this round.
  ///
  /// Doubles as the rank handed to the scoring rule, so a steal after two
  /// failed attempts is automatically worth less than the first press.
  final int resolvedAttempts;
  final bool buzzerAnswerCorrect;
  final bool buzzerOpenForAll;
  final Map<String, int> buzzerVerdicts;

  /// Host decisions for written answers: one for correct, zero for incorrect.
  final Map<String, int> answerVerdicts;
  final bool recoverySoftTimer;
  final int? timerRestartedAtHostMicros;
  // Later timer restarts must not change the scoring time of accepted input.
  final Map<String, int> acceptedElapsedMicros;

  /// Set in a "Biggest Snowflake" round: answers are not compared with a
  /// solution but with each other, and the rarest one wins.
  final SnowflakeScoring? snowflake;

  /// Number of answers withheld from a guest snapshot until the reveal
  /// (poker and snowflake rounds); `0` on the host.
  final int hiddenAnswerCount;

  /// Answers are given aloud and judged by the host (verbal answer mode).
  ///
  /// Players may still type an answer, but every answer is graded manually
  /// and the host may also judge players that did not submit anything.
  final bool verbal;

  /// Host instants at which the hints of the question were shown, in order;
  /// its length is the number of hints on stage.
  final List<int> hintTimesMicros;

  /// Number of hints the guests currently see.
  int get shownHintCount {
    final total = question?.hints.length ?? 0;
    return hintTimesMicros.length < total ? hintTimesMicros.length : total;
  }

  /// The hints the guests currently see, in order.
  List<QuestionHint> get shownHints =>
      question?.hints.sublist(0, shownHintCount) ?? const [];

  /// The hint the host may show next, `null` when none is left.
  QuestionHint? get nextHint =>
      question?.hints.skip(shownHintCount).firstOrNull;

  /// Points a correct answer given at [hostMicros] earns less, i.e. the cost
  /// of the hints that were already shown at that instant.
  int hintDeductionAt(int hostMicros) {
    var total = 0;
    for (final (index, hint) in shownHints.indexed) {
      if (hintTimesMicros[index] <= hostMicros) total += hint.cost;
    }
    return total;
  }

  /// Points a correct answer given now earns less.
  int get hintDeduction =>
      shownHints.fold(0, (total, hint) => total + hint.cost);

  /// Whether the host judges the answers of this round instead of the
  /// question's own evaluation. Buzzer rounds are always judged live.
  bool get manualGrading {
    final current = question;
    if (current == null || current is BuzzerQuestion) return false;
    return verbal || current.requiresManualGrading;
  }

  /// Number of submitted answers, including withheld ones.
  int get answerCount => answers.length + hiddenAnswerCount;

  /// The distinct answers of a snowflake round, rarest first; empty in every
  /// other round.
  List<SnowflakeGroup> get snowflakeGroups {
    final current = question;
    final scoring = snowflake;
    if (current == null || scoring == null) return const [];
    final keys = <String, String>{
      for (final answer in answers.values)
        answer.playerId: ?current.uniquenessKey(answer),
    };
    final shares = snowflakeShares(
      keys,
      graded: scoring == SnowflakeScoring.graded,
    );
    final members = <String, List<String>>{};
    for (final entry in keys.entries) {
      (members[entry.value] ??= []).add(entry.key);
    }
    return [
      for (final entry in members.entries)
        SnowflakeGroup(
          key: entry.key,
          playerIds: entry.value,
          share: shares[entry.value.first]!,
        ),
    ]..sort((a, b) {
      final bySize = a.playerIds.length.compareTo(b.playerIds.length);
      return bySize != 0 ? bySize : a.key.compareTo(b.key);
    });
  }

  int? get timerStartedAtHostMicros =>
      timerRestartedAtHostMicros ?? startedAtHostMicros;
  bool get hasSoftTimer => recoverySoftTimer || question?.softTimeLimit == true;

  /// Number of submitted answers still awaiting a host decision.
  int get pendingGradeCount => manualGrading
      ? answers.keys.where((id) => !answerVerdicts.containsKey(id)).length
      : 0;

  /// Returns the effective accuracy, or `null` while manual grading is pending.
  double? accuracyFor(AnswerSubmission answer) {
    final current = question;
    if (current == null) return null;
    if (snowflake != null) {
      // Guests only receive the answers of the others with the reveal.
      for (final group in snowflakeGroups) {
        if (group.playerIds.contains(answer.playerId)) return group.share;
      }
      return null;
    }
    return manualGrading
        ? answerVerdicts[answer.playerId]?.toDouble()
        : current.accuracy(answer);
  }

  /// The fastest press, or `null` while nobody buzzed.
  BuzzerPress? get fastestPress =>
      buzzerQueue.isEmpty ? null : buzzerQueue.first;

  /// The next press that is allowed to take the floor, or `null`.
  BuzzerPress? get nextCandidate {
    for (final press in buzzerQueue) {
      if (!lockedOutPlayerIds.contains(press.playerId)) return press;
    }
    return null;
  }

  /// Zero based buzzer rank of [playerId], or `-1` when they did not buzz.
  int rankOf(String playerId) =>
      buzzerQueue.indexWhere((press) => press.playerId == playerId);

  /// Whether [playerId] already produced input for this round.
  bool hasSubmitted(String playerId) =>
      answers.containsKey(playerId) || rankOf(playerId) >= 0;

  /// Time between the round start and [hostMicros].
  Duration elapsedAt(int hostMicros) =>
      _elapsedSince(startedAtHostMicros, hostMicros);

  Duration timerElapsedAt(int hostMicros) =>
      _elapsedSince(timerStartedAtHostMicros, hostMicros);

  Duration _elapsedSince(int? startedAt, int hostMicros) {
    if (startedAt == null) return Duration.zero;
    final elapsed = hostMicros - startedAt;
    return Duration(microseconds: elapsed < 0 ? 0 : elapsed);
  }

  /// Gap between [press] and the fastest press of the round.
  Duration gapToFastest(BuzzerPress press) {
    final fastest = fastestPress;
    if (fastest == null) return Duration.zero;
    return Duration(
      microseconds: press.hostTimestampMicros - fastest.hostTimestampMicros,
    );
  }

  /// Returns a copy with the given fields replaced.
  RoundState copyWith({
    Object? question = _unset,
    RoundStatus? status,
    Object? startedAtHostMicros = _unset,
    List<BuzzerPress>? buzzerQueue,
    Map<String, AnswerSubmission>? answers,
    Object? activePlayerId = _unset,
    Set<String>? lockedOutPlayerIds,
    int? resolvedAttempts,
    bool? buzzerAnswerCorrect,
    bool? buzzerOpenForAll,
    Map<String, int>? buzzerVerdicts,
    Map<String, int>? answerVerdicts,
    bool? recoverySoftTimer,
    Object? timerRestartedAtHostMicros = _unset,
    Map<String, int>? acceptedElapsedMicros,
    int? hiddenAnswerCount,
    bool? verbal,
    List<int>? hintTimesMicros,
  }) => RoundState(
    hintTimesMicros: hintTimesMicros ?? this.hintTimesMicros,
    snowflake: snowflake,
    verbal: verbal ?? this.verbal,
    hiddenAnswerCount: hiddenAnswerCount ?? this.hiddenAnswerCount,
    question: identical(question, _unset)
        ? this.question
        : question as Question?,
    status: status ?? this.status,
    startedAtHostMicros: identical(startedAtHostMicros, _unset)
        ? this.startedAtHostMicros
        : startedAtHostMicros as int?,
    buzzerQueue: buzzerQueue ?? this.buzzerQueue,
    answers: answers ?? this.answers,
    activePlayerId: identical(activePlayerId, _unset)
        ? this.activePlayerId
        : activePlayerId as String?,
    lockedOutPlayerIds: lockedOutPlayerIds ?? this.lockedOutPlayerIds,
    resolvedAttempts: resolvedAttempts ?? this.resolvedAttempts,
    buzzerAnswerCorrect: buzzerAnswerCorrect ?? this.buzzerAnswerCorrect,
    buzzerOpenForAll: buzzerOpenForAll ?? this.buzzerOpenForAll,
    buzzerVerdicts: buzzerVerdicts ?? this.buzzerVerdicts,
    answerVerdicts: answerVerdicts ?? this.answerVerdicts,
    recoverySoftTimer: recoverySoftTimer ?? this.recoverySoftTimer,
    timerRestartedAtHostMicros: identical(timerRestartedAtHostMicros, _unset)
        ? this.timerRestartedAtHostMicros
        : timerRestartedAtHostMicros as int?,
    acceptedElapsedMicros: acceptedElapsedMicros ?? this.acceptedElapsedMicros,
  );

  /// Serializes the round.
  JsonMap toJson() => {
    'question': question?.toJson(),
    'status': status.name,
    'startedAtHostMicros': startedAtHostMicros,
    'buzzerQueue': buzzerQueue
        .map((press) => press.toJson())
        .toList(growable: false),
    'answers': answers.map((key, value) => MapEntry(key, value.toJson())),
    'activePlayerId': activePlayerId,
    'lockedOutPlayerIds': lockedOutPlayerIds.toList(growable: false),
    'resolvedAttempts': resolvedAttempts,
    'buzzerAnswerCorrect': buzzerAnswerCorrect,
    'buzzerOpenForAll': buzzerOpenForAll,
    'buzzerVerdicts': buzzerVerdicts,
    'answerVerdicts': answerVerdicts,
    'recoverySoftTimer': recoverySoftTimer,
    'timerRestartedAtHostMicros': timerRestartedAtHostMicros,
    'acceptedElapsedMicros': acceptedElapsedMicros,
    // Only written when set: saved games of older versions stay complete.
    if (snowflake != null) 'snowflake': snowflake!.name,
    if (hiddenAnswerCount != 0) 'hiddenAnswerCount': hiddenAnswerCount,
    if (verbal) 'verbal': true,
    if (hintTimesMicros.isNotEmpty) 'hintTimesMicros': hintTimesMicros,
  };

  @override
  List<Object?> get props => [
    question,
    status,
    startedAtHostMicros,
    buzzerQueue,
    answers,
    activePlayerId,
    lockedOutPlayerIds,
    resolvedAttempts,
    buzzerAnswerCorrect,
    buzzerOpenForAll,
    buzzerVerdicts,
    answerVerdicts,
    recoverySoftTimer,
    timerRestartedAtHostMicros,
    acceptedElapsedMicros,
    snowflake,
    hiddenAnswerCount,
    verbal,
    hintTimesMicros,
  ];
}
