/// The one place that decides who is ahead of whom.
library;

import 'game_state.dart';
import 'player.dart';
import 'team.dart';

/// Assigns competition places (1, 1, 3, …) to [entries], best first.
///
/// [compare] returns a negative value when its first argument is ahead and 0
/// for a shared place; [tieBreak] only orders entries that share a place.
List<(T, int)> rankEntries<T>(
  Iterable<T> entries,
  int Function(T a, T b) compare, {
  int Function(T a, T b)? tieBreak,
}) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final order = compare(a, b);
      return order != 0 || tieBreak == null ? order : tieBreak(a, b);
    });
  final ranked = <(T, int)>[];
  for (final (index, entry) in sorted.indexed) {
    ranked.add((
      entry,
      index > 0 && compare(sorted[index - 1], entry) == 0
          ? ranked[index - 1].$2
          : index + 1,
    ));
  }
  return ranked;
}

/// Compares two team ids of [game]; negative when [a] is ahead.
///
/// In a poker session teams with chips come first, then teams that have none
/// but are still in the game (all-in), then the eliminated ones with the last
/// one to leave first.
int compareTeams(GameState game, String a, String b) {
  final scores = game.teamScores;
  final byScore = (scores[b] ?? 0).compareTo(scores[a] ?? 0);
  final poker = game.poker;
  if (byScore != 0 || poker == null) return byScore;
  final outA = poker.eliminations[a];
  final outB = poker.eliminations[b];
  if (outA == outB) return 0;
  if (outA == null) return -1;
  if (outB == null) return 1;
  return outB.compareTo(outA);
}

/// All teams of [game] with their place, best first.
List<(Team, int)> rankTeams(GameState game) => rankEntries(
  game.teams.values,
  (a, b) => compareTeams(game, a.id, b.id),
  tieBreak: (a, b) => _byName(a.name, b.name, a.id, b.id),
);

/// All players of [game] with their place, best first.
List<(Player, int)> rankPlayers(GameState game) => rankEntries(
  game.players.values,
  (a, b) => game.scores.scoreOf(b.id).compareTo(game.scores.scoreOf(a.id)),
  tieBreak: (a, b) => _byName(a.name, b.name, a.id, b.id),
);

int _byName(String nameA, String nameB, String idA, String idB) {
  final order = nameA.toLowerCase().compareTo(nameB.toLowerCase());
  return order != 0 ? order : idA.compareTo(idB);
}
