/// State of the round that is currently on stage.
library;

import 'package:equatable/equatable.dart';

import 'answer.dart';
import 'json.dart';
import 'question.dart';

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
  });

  /// Restores a round from [json].
  factory RoundState.fromJson(JsonMap json) => RoundState(
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

  /// Number of submitted answers still awaiting a host decision.
  int get pendingGradeCount => question?.requiresManualGrading == true
      ? answers.keys.where((id) => !answerVerdicts.containsKey(id)).length
      : 0;

  /// Returns the effective accuracy, or `null` while manual grading is pending.
  double? accuracyFor(AnswerSubmission answer) {
    final current = question;
    if (current == null) return null;
    return current.requiresManualGrading
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
  Duration elapsedAt(int hostMicros) {
    final startedAt = startedAtHostMicros;
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
  }) => RoundState(
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
  ];
}
