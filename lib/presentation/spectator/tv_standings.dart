/// View model of the TV leaderboard.
library;

import 'package:equatable/equatable.dart';

import '../../core/models/models.dart';

/// One row of the TV leaderboard.
final class TvStanding extends Equatable {
  /// Creates a leaderboard row.
  const TvStanding({
    required this.rank,
    required this.label,
    required this.points,
    this.colorValue,
    this.subtitle,
    this.isOnline = true,
  });

  /// One based position; ties share the better rank.
  final int rank;

  /// Player or team name.
  final String label;

  /// Total points.
  final int points;

  /// Optional team accent as 32 bit ARGB.
  final int? colorValue;

  /// Secondary line, for example the members of a team.
  final String? subtitle;

  /// Whether the player (or any member of the team) is connected.
  final bool isOnline;

  @override
  List<Object?> get props => [
    rank,
    label,
    points,
    colorValue,
    subtitle,
    isOnline,
  ];
}

/// The visible part of the leaderboard plus the number of cut-off rows.
final class TvStandings extends Equatable {
  /// Creates the leaderboard view model.
  const TvStandings({required this.entries, required this.hiddenCount});

  /// Rows that fit on screen.
  final List<TvStanding> entries;

  /// Rows that were truncated.
  final int hiddenCount;

  @override
  List<Object?> get props => [entries, hiddenCount];
}

/// Derives the leaderboard from [game], honouring [GameState.mode].
///
/// Solo mode ranks players, team mode ranks teams. A large display cannot
/// scroll, so at most [maxEntries] rows are returned and the rest is counted.
TvStandings buildTvStandings(GameState game, {int maxEntries = 8}) {
  final rows = switch (game.mode) {
    SoloMode() => _playerRows(game),
    TeamMode() => _teamRows(game),
  };

  final visible = rows.take(maxEntries).toList(growable: false);
  return TvStandings(
    entries: visible,
    hiddenCount: rows.length - visible.length,
  );
}

List<TvStanding> _playerRows(GameState game) {
  final players = game.players.values.toList(growable: false)
    ..sort((a, b) {
      final byScore = game.scores.scoreOf(b.id).compareTo(
        game.scores.scoreOf(a.id),
      );
      return byScore != 0
          ? byScore
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  return _ranked(
    [
      for (final player in players)
        (
          points: game.scores.scoreOf(player.id),
          build: (int rank) => TvStanding(
            rank: rank,
            label: player.name,
            points: game.scores.scoreOf(player.id),
            colorValue: switch (game.teams[player.teamId]) {
              final Team team => team.colorValue,
              null => null,
            },
            isOnline: player.isConnected,
          ),
        ),
    ],
  );
}

List<TvStanding> _teamRows(GameState game) {
  final totals = game.teamScores;
  final teams = game.teams.values.toList(growable: false)
    ..sort((a, b) {
      final byScore = (totals[b.id] ?? 0).compareTo(totals[a.id] ?? 0);
      return byScore != 0
          ? byScore
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  return _ranked(
    [
      for (final team in teams)
        (
          points: totals[team.id] ?? 0,
          build: (int rank) {
            final members = game.players.values
                .where((player) => player.teamId == team.id)
                .toList(growable: false);
            return TvStanding(
              rank: rank,
              label: team.name,
              points: totals[team.id] ?? 0,
              colorValue: team.colorValue,
              subtitle: members.isEmpty
                  ? null
                  : members.map((player) => player.name).join(' · '),
              isOnline: members.any((player) => player.isConnected),
            );
          },
        ),
    ],
  );
}

/// Assigns competition ranks (1, 1, 3, …) to rows that are already sorted.
List<TvStanding> _ranked(
  List<({int points, TvStanding Function(int rank) build})> sorted,
) {
  final result = <TvStanding>[];
  var rank = 0;
  int? previousPoints;
  for (var index = 0; index < sorted.length; index++) {
    final row = sorted[index];
    if (row.points != previousPoints) rank = index + 1;
    previousPoints = row.points;
    result.add(row.build(rank));
  }
  return result;
}

