/// Score bookkeeping for solo and team play.
library;

import 'package:equatable/equatable.dart';

import '../engine/scoring_rules.dart';
import 'json.dart';
import 'player.dart';

/// One immutable entry of the score history.
///
/// Keeping the history instead of only the totals makes the host feed
/// explainable ("why does Team Red have 35 points?") and is the foundation for
/// an undo feature.
final class ScoreEvent extends Equatable {
  /// Creates a history entry.
  const ScoreEvent({
    required this.playerId,
    required this.questionId,
    required this.points,
    required this.reason,
    required this.atHostMicros,
    this.teamId,
  });

  /// Restores an entry from [json].
  factory ScoreEvent.fromJson(JsonMap json) => ScoreEvent(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    points: json.readInt('points'),
    reason: json.readString('reason'),
    atHostMicros: json.readInt('atHostMicros'),
    teamId: json.readStringOrNull('teamId'),
  );

  /// Player the points were booked on; empty for a direct team booking.
  final String playerId;

  /// Team the points were booked on directly (without a player), or `null`.
  ///
  /// Only manual point changes of the quizmaster book on a team directly.
  final String? teamId;

  /// Question that produced the points; empty when the booking is not bound
  /// to a question (manual point change between questions).
  final String questionId;

  /// Signed amount.
  final int points;

  /// Explanation provided by the [ScoringRule].
  final String reason;

  /// Instant on the host timeline.
  final int atHostMicros;

  /// Whether the entry is a direct team booking.
  bool get isTeamBooking => teamId != null;

  /// Serializes the entry.
  JsonMap toJson() => {
    'playerId': playerId,
    'questionId': questionId,
    'points': points,
    'reason': reason,
    'atHostMicros': atHostMicros,
    if (teamId != null) 'teamId': teamId,
  };

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    points,
    reason,
    atHostMicros,
    teamId,
  ];
}

/// Aggregated scores of the running session.
final class ScoreState extends Equatable {
  /// Creates a score board.
  const ScoreState({
    this.byPlayer = const {},
    this.history = const [],
    this.byTeam = const {},
  });

  /// Restores the board from [json].
  factory ScoreState.fromJson(JsonMap json) => ScoreState(
    byPlayer: json.readIntMap('byPlayer'),
    history: json.readList('history', ScoreEvent.fromJson),
    byTeam: json['byTeam'] == null ? const {} : json.readIntMap('byTeam'),
  );

  /// Current total per player id.
  final Map<String, int> byPlayer;

  /// Points booked on a team directly (manual point changes), per team id.
  ///
  /// They count towards [teamTotals] but belong to no single player.
  final Map<String, int> byTeam;

  /// Chronological list of every booking.
  final List<ScoreEvent> history;

  /// Returns the total of [playerId], defaulting to zero.
  int scoreOf(String playerId) => byPlayer[playerId] ?? 0;

  /// Returns a board that contains a zero entry for [playerId].
  ScoreState withParticipant(String playerId) => byPlayer.containsKey(playerId)
      ? this
      : copyWith(byPlayer: {...byPlayer, playerId: 0});

  /// Returns a copy with the given fields replaced.
  ScoreState copyWith({
    Map<String, int>? byPlayer,
    List<ScoreEvent>? history,
    Map<String, int>? byTeam,
  }) => ScoreState(
    byPlayer: byPlayer ?? this.byPlayer,
    history: history ?? this.history,
    byTeam: byTeam ?? this.byTeam,
  );

  /// Books [delta] on [playerId] and appends a matching [ScoreEvent].
  ScoreState apply({
    required String playerId,
    required String questionId,
    required ScoreDelta delta,
    required int atHostMicros,
  }) {
    if (delta.points == 0) return withParticipant(playerId);
    return copyWith(
      byPlayer: {...byPlayer, playerId: scoreOf(playerId) + delta.points},
      history: [
        ...history,
        ScoreEvent(
          playerId: playerId,
          questionId: questionId,
          points: delta.points,
          reason: delta.reason,
          atHostMicros: atHostMicros,
        ),
      ],
    );
  }

  /// Books [delta] directly on [teamId] without attributing it to a player.
  ScoreState applyToTeam({
    required String teamId,
    required String questionId,
    required ScoreDelta delta,
    required int atHostMicros,
  }) {
    if (delta.points == 0) return this;
    return copyWith(
      byTeam: {...byTeam, teamId: (byTeam[teamId] ?? 0) + delta.points},
      history: [
        ...history,
        ScoreEvent(
          playerId: '',
          teamId: teamId,
          questionId: questionId,
          points: delta.points,
          reason: delta.reason,
          atHostMicros: atHostMicros,
        ),
      ],
    );
  }

  /// Moves the points [playerId] earned to a direct booking of [teamId].
  ///
  /// With teams, points belong to the team: before a player leaves it (team
  /// change or removal), their points stay with the team they were earned
  /// for. Both bookings carry no question, so they never count as a win.
  ScoreState handOverToTeam({
    required String playerId,
    required String teamId,
    required int atHostMicros,
  }) {
    final points = scoreOf(playerId);
    if (points == 0) return this;
    return apply(
      playerId: playerId,
      questionId: '',
      delta: ScoreDelta(-points, reason: 'Team handover'),
      atHostMicros: atHostMicros,
    ).applyToTeam(
      teamId: teamId,
      questionId: '',
      delta: ScoreDelta(points, reason: 'Team handover'),
      atHostMicros: atHostMicros,
    );
  }

  /// Aggregates the player totals into team totals.
  ///
  /// Players without a team are ignored, which makes the method safe to call in
  /// solo mode as well. Direct team bookings ([byTeam]) are added on top.
  Map<String, int> teamTotals(Iterable<Player> players) {
    final totals = <String, int>{};
    for (final player in players) {
      final teamId = player.teamId;
      if (teamId == null) continue;
      totals[teamId] = (totals[teamId] ?? 0) + scoreOf(player.id);
    }
    for (final entry in byTeam.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
    return totals;
  }

  /// Returns the player totals sorted from best to worst.
  List<MapEntry<String, int>> get ranking =>
      byPlayer.entries.toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value));

  /// Serializes the board.
  JsonMap toJson() => {
    'byPlayer': byPlayer,
    'history': history.map((event) => event.toJson()).toList(growable: false),
    if (byTeam.isNotEmpty) 'byTeam': byTeam,
  };

  @override
  List<Object?> get props => [byPlayer, history, byTeam];
}
