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
  });

  /// Restores an entry from [json].
  factory ScoreEvent.fromJson(JsonMap json) => ScoreEvent(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    points: json.readInt('points'),
    reason: json.readString('reason'),
    atHostMicros: json.readInt('atHostMicros'),
  );

  /// Player the points were booked on.
  final String playerId;

  /// Question that produced the points.
  final String questionId;

  /// Signed amount.
  final int points;

  /// Explanation provided by the [ScoringRule].
  final String reason;

  /// Instant on the host timeline.
  final int atHostMicros;

  /// Serializes the entry.
  JsonMap toJson() => {
    'playerId': playerId,
    'questionId': questionId,
    'points': points,
    'reason': reason,
    'atHostMicros': atHostMicros,
  };

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    points,
    reason,
    atHostMicros,
  ];
}

/// Aggregated scores of the running session.
final class ScoreState extends Equatable {
  /// Creates a score board.
  const ScoreState({this.byPlayer = const {}, this.history = const []});

  /// Restores the board from [json].
  factory ScoreState.fromJson(JsonMap json) => ScoreState(
    byPlayer: json.readIntMap('byPlayer'),
    history: json.readList('history', ScoreEvent.fromJson),
  );

  /// Current total per player id.
  final Map<String, int> byPlayer;

  /// Chronological list of every booking.
  final List<ScoreEvent> history;

  /// Returns the total of [playerId], defaulting to zero.
  int scoreOf(String playerId) => byPlayer[playerId] ?? 0;

  /// Returns a board that contains a zero entry for [playerId].
  ScoreState withParticipant(String playerId) => byPlayer.containsKey(playerId)
      ? this
      : ScoreState(byPlayer: {...byPlayer, playerId: 0}, history: history);

  /// Books [delta] on [playerId] and appends a matching [ScoreEvent].
  ScoreState apply({
    required String playerId,
    required String questionId,
    required ScoreDelta delta,
    required int atHostMicros,
  }) {
    if (delta.points == 0) return withParticipant(playerId);
    return ScoreState(
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

  /// Aggregates the player totals into team totals.
  ///
  /// Players without a team are ignored, which makes the method safe to call in
  /// solo mode as well.
  Map<String, int> teamTotals(Iterable<Player> players) {
    final totals = <String, int>{};
    for (final player in players) {
      final teamId = player.teamId;
      if (teamId == null) continue;
      totals[teamId] = (totals[teamId] ?? 0) + scoreOf(player.id);
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
  };

  @override
  List<Object?> get props => [byPlayer, history];
}
