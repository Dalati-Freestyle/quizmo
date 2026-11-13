/// The game protocol that players and TV screens receive when a game ends.
///
/// It bundles everything the host logged for the session in a form that is
/// safe to hand to guests once the quiz is over: final standings, every
/// question with its solution, the answers of all players and the full
/// correction history with reasons. Credentials and operational data (guest
/// Wi-Fi, access keys, server log) are never part of it.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

/// Status of one answer in the protocol.
enum ProtocolAnswerStatus {
  correct,
  partial,
  incorrect,
  ungraded,
  noAnswer,
  notEligible,
  teamAnswered,
}

/// One row of the final standings.
final class ProtocolStanding extends Equatable {
  /// Creates a standing row.
  const ProtocolStanding({
    required this.id,
    required this.name,
    required this.isTeam,
    required this.score,
    required this.place,
    this.memberIds = const [],
    this.memberNames = const [],
  });

  /// Restores a row from [json].
  factory ProtocolStanding.fromJson(JsonMap json) => ProtocolStanding(
    id: json.readString('id'),
    name: json.readString('name'),
    isTeam: json.readBool('isTeam'),
    score: json.readInt('score'),
    place: json.readInt('place'),
    memberIds: json['memberIds'] == null
        ? const []
        : json.readStringList('memberIds'),
    memberNames: json['memberNames'] == null
        ? const []
        : json.readStringList('memberNames'),
  );

  /// Team or player id.
  final String id;

  /// Display name.
  final String name;

  /// Whether the row is a team.
  final bool isTeam;

  /// Final points (chips in a poker session).
  final int score;

  /// One-based place; ties share the same place (1, 1, 3, …).
  final int place;

  /// Players of a team row.
  final List<String> memberIds;

  /// Names of [memberIds], in the same order.
  final List<String> memberNames;

  /// Serializes the row.
  JsonMap toJson() => {
    'id': id,
    'name': name,
    'isTeam': isTeam,
    'score': score,
    'place': place,
    if (memberIds.isNotEmpty) 'memberIds': memberIds,
    if (memberNames.isNotEmpty) 'memberNames': memberNames,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    isTeam,
    score,
    place,
    memberIds,
    memberNames,
  ];
}

/// One answer of one player to one played question.
final class ProtocolAnswer extends Equatable {
  /// Creates an answer row.
  const ProtocolAnswer({
    required this.playerId,
    required this.player,
    required this.status,
    this.team,
    this.answer,
    this.points,
    this.wager,
    this.practice = false,
  });

  /// Restores a row from [json].
  factory ProtocolAnswer.fromJson(JsonMap json) => ProtocolAnswer(
    playerId: json.readString('playerId'),
    player: json.readString('player'),
    team: json.readStringOrNull('team'),
    answer: json.readStringOrNull('answer'),
    status: ProtocolAnswerStatus.values.firstWhere(
      (status) => status.name == json.readString('status'),
      orElse: () => throw const JsonContractException('Unknown status.'),
    ),
    points: json.readIntOrNull('points'),
    wager: json.readIntOrNull('wager'),
    practice: json.readBool('practice'),
  );

  /// Player id.
  final String playerId;

  /// Player name at the time of the question.
  final String player;

  /// Team name, if the session runs in teams.
  final String? team;

  /// Readable answer, `null` when the player did not answer.
  final String? answer;

  /// Result of the answer.
  final ProtocolAnswerStatus status;

  /// Points the player earned with this question (chips change of the team
  /// in a poker session), `null` when nothing was booked.
  final int? points;

  /// Poker stake of the player's team.
  final int? wager;

  /// Whether the team only played for practice (bankrupt poker team).
  final bool practice;

  /// Serializes the row.
  JsonMap toJson() => {
    'playerId': playerId,
    'player': player,
    'team': team,
    'answer': answer,
    'status': status.name,
    'points': points,
    'wager': wager,
    'practice': practice,
  };

  @override
  List<Object?> get props => [
    playerId,
    player,
    team,
    answer,
    status,
    points,
    wager,
    practice,
  ];
}

/// One played question (a Jeopardy steal round is a question of its own).
final class ProtocolQuestion extends Equatable {
  /// Creates a question entry.
  const ProtocolQuestion({
    required this.number,
    required this.questionId,
    required this.prompt,
    required this.solution,
    required this.answers,
    this.category,
    this.pointsAtStake,
    this.isSteal = false,
    this.isDailyDouble = false,
  });

  /// Restores an entry from [json].
  factory ProtocolQuestion.fromJson(JsonMap json) => ProtocolQuestion(
    number: json.readInt('number'),
    questionId: json.readString('questionId'),
    prompt: json.readString('prompt'),
    solution: json.readString('solution'),
    category: json.readStringOrNull('category'),
    pointsAtStake: json.readIntOrNull('pointsAtStake'),
    isSteal: json.readBool('isSteal'),
    isDailyDouble: json.readBool('isDailyDouble'),
    answers: json.readList('answers', ProtocolAnswer.fromJson),
  );

  /// One-based position in the order of play.
  final int number;

  /// Question id.
  final String questionId;

  /// Question text.
  final String prompt;

  /// Readable solution.
  final String solution;

  /// Jeopardy category, if any.
  final String? category;

  /// Points of the Jeopardy row or the Daily Double wager.
  final int? pointsAtStake;

  /// Whether this is a Jeopardy steal round.
  final bool isSteal;

  /// Whether the question was a Daily Double.
  final bool isDailyDouble;

  /// Answers of all players.
  final List<ProtocolAnswer> answers;

  /// Serializes the entry.
  JsonMap toJson() => {
    'number': number,
    'questionId': questionId,
    'prompt': prompt,
    'solution': solution,
    'category': category,
    'pointsAtStake': pointsAtStake,
    'isSteal': isSteal,
    'isDailyDouble': isDailyDouble,
    'answers': answers.map((answer) => answer.toJson()).toList(),
  };

  @override
  List<Object?> get props => [
    number,
    questionId,
    prompt,
    solution,
    category,
    pointsAtStake,
    isSteal,
    isDailyDouble,
    answers,
  ];
}

/// Kind of a logged correction.
enum ProtocolCorrectionKind { answer, buzzer, points, chips }

/// One entry of the host's correction history.
final class ProtocolCorrection extends Equatable {
  /// Creates an entry.
  const ProtocolCorrection({
    required this.atMicros,
    required this.kind,
    required this.target,
    this.question,
    this.before,
    this.after,
    this.delta,
    this.reason,
    this.isReversal = false,
  });

  /// Restores an entry from [json].
  factory ProtocolCorrection.fromJson(JsonMap json) => ProtocolCorrection(
    atMicros: json.readInt('atMicros'),
    kind: ProtocolCorrectionKind.values.firstWhere(
      (kind) => kind.name == json.readString('kind'),
      orElse: () => throw const JsonContractException('Unknown kind.'),
    ),
    target: json.readString('target'),
    question: json.readStringOrNull('question'),
    before: json.readIntOrNull('before'),
    after: json.readIntOrNull('after'),
    delta: json.readIntOrNull('delta'),
    reason: json.readStringOrNull('reason'),
    isReversal: json.readBool('isReversal'),
  );

  /// Instant on the host timeline.
  final int atMicros;

  /// What was corrected.
  final ProtocolCorrectionKind kind;

  /// Affected player or team (“Team / Player” in team mode).
  final String target;

  /// Prompt of the affected question, `null` for a free point change.
  final String? question;

  /// Value before the change (points, chips, or 1/0 for a verdict).
  final int? before;

  /// Value after the change.
  final int? after;

  /// Signed points or chips the change booked.
  final int? delta;

  /// Reason given by the quizmaster.
  final String? reason;

  /// Whether the entry reverses an earlier one.
  final bool isReversal;

  /// Serializes the entry.
  JsonMap toJson() => {
    'atMicros': atMicros,
    'kind': kind.name,
    'target': target,
    'question': question,
    'before': before,
    'after': after,
    'delta': delta,
    'reason': reason,
    'isReversal': isReversal,
  };

  @override
  List<Object?> get props => [
    atMicros,
    kind,
    target,
    question,
    before,
    after,
    delta,
    reason,
    isReversal,
  ];
}

/// Complete protocol of a finished game.
final class GameProtocol extends Equatable {
  /// Creates a protocol.
  const GameProtocol({
    required this.title,
    required this.generatedAtMicros,
    required this.format,
    required this.teamMode,
    required this.standings,
    required this.questions,
    required this.corrections,
  });

  /// Restores a protocol from [json].
  factory GameProtocol.fromJson(JsonMap json) => GameProtocol(
    title: json.readString('title'),
    generatedAtMicros: json.readInt('generatedAtMicros'),
    format: ProtocolFormat.values.firstWhere(
      (format) => format.name == json.readString('format'),
      orElse: () => throw const JsonContractException('Unknown format.'),
    ),
    teamMode: json.readBool('teamMode'),
    standings: json.readList('standings', ProtocolStanding.fromJson),
    questions: json.readList('questions', ProtocolQuestion.fromJson),
    corrections: json.readList('corrections', ProtocolCorrection.fromJson),
  );

  /// Quiz title.
  final String title;

  /// Instant (host timeline) the protocol was generated.
  final int generatedAtMicros;

  /// Quiz format of the session.
  final ProtocolFormat format;

  /// Whether teams (not players) are ranked.
  final bool teamMode;

  /// Final standings, best first.
  final List<ProtocolStanding> standings;

  /// Played questions in the order of play.
  final List<ProtocolQuestion> questions;

  /// Correction history in chronological order.
  final List<ProtocolCorrection> corrections;

  /// Whether scores are chips.
  bool get usesChips => format == ProtocolFormat.poker;

  /// Standing that contains [playerId] (their own row or their team).
  ProtocolStanding? standingOf(String? playerId) {
    if (playerId == null) return null;
    for (final standing in standings) {
      if (standing.id == playerId && !standing.isTeam) return standing;
      if (standing.isTeam && standing.memberIds.contains(playerId)) {
        return standing;
      }
    }
    return null;
  }

  /// Serializes the protocol.
  JsonMap toJson() => {
    'title': title,
    'generatedAtMicros': generatedAtMicros,
    'format': format.name,
    'teamMode': teamMode,
    'standings': standings.map((row) => row.toJson()).toList(),
    'questions': questions.map((question) => question.toJson()).toList(),
    'corrections': corrections.map((entry) => entry.toJson()).toList(),
  };

  @override
  List<Object?> get props => [
    title,
    generatedAtMicros,
    format,
    teamMode,
    standings,
    questions,
    corrections,
  ];
}

/// Quiz format recorded in a protocol.
enum ProtocolFormat { standard, jeopardy, poker }

/// Assigns competition places (1, 1, 3, …) to [scores], best first.
///
/// Returns the entries sorted by score (descending) and then by [tieBreak].
List<(T, int)> rankByScore<T>(
  Iterable<T> entries,
  int Function(T entry) score, {
  int Function(T a, T b)? tieBreak,
}) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      return byScore != 0 || tieBreak == null ? byScore : tieBreak(a, b);
    });
  final ranked = <(T, int)>[];
  for (final (index, entry) in sorted.indexed) {
    final place = index > 0 && score(sorted[index - 1]) == score(entry)
        ? ranked[index - 1].$2
        : index + 1;
    ranked.add((entry, place));
  }
  return ranked;
}
