/// Leaderboard view model of the TV screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/spectator/tv_standings.dart';

void main() {
  const red = Team(id: 'red', name: 'Red Foxes', colorValue: 0xFFFF0000);
  const blue = Team(id: 'blue', name: 'Blue Whales', colorValue: 0xFF0000FF);

  GameState soloGame(Map<String, int> points) => GameState(
    players: {
      for (final id in points.keys) id: Player(id: id, name: id.toUpperCase()),
    },
    scores: ScoreState(byPlayer: points),
  );

  test('ranks players by score and shares the rank on ties', () {
    final standings = buildTvStandings(soloGame({'a': 10, 'b': 30, 'c': 10}));

    expect(standings.entries.map((e) => e.label), ['B', 'A', 'C']);
    expect(standings.entries.map((e) => e.rank), [1, 2, 2]);
    expect(standings.hiddenCount, 0);
  });

  test('truncates to maxEntries and counts the hidden rows', () {
    final game = soloGame({for (var i = 0; i < 12; i++) 'p$i': i});

    final standings = buildTvStandings(game, maxEntries: 8);

    expect(standings.entries, hasLength(8));
    expect(standings.hiddenCount, 4);
    expect(standings.entries.first.points, 11);
  });

  test('ranks teams in team mode and lists their members', () {
    final game = GameState(
      mode: const TeamMode(),
      teams: const {'red': red, 'blue': blue},
      players: const {
        'a': Player(id: 'a', name: 'Ada', teamId: 'red'),
        'b': Player(id: 'b', name: 'Bob', teamId: 'blue'),
        'c': Player(id: 'c', name: 'Cy', teamId: 'blue', isConnected: false),
      },
      scores: const ScoreState(byPlayer: {'a': 5, 'b': 10, 'c': 10}),
    );

    final standings = buildTvStandings(game);

    expect(standings.entries.map((e) => e.label), ['Blue Whales', 'Red Foxes']);
    expect(standings.entries.first.points, 20);
    expect(standings.entries.first.subtitle, 'Bob · Cy');
    expect(standings.entries.first.colorValue, 0xFF0000FF);
  });

  test('marks a team offline when no member is connected', () {
    final game = GameState(
      mode: const TeamMode(),
      teams: const {'red': red},
      players: const {
        'a': Player(id: 'a', name: 'Ada', teamId: 'red', isConnected: false),
      },
    );

    expect(buildTvStandings(game).entries.single.isOnline, isFalse);
  });
}

