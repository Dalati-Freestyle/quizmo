import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/session_notifications.dart';

void main() {
  testWidgets(
    'connection transitions and all answered create visible notifications',
    (tester) async {
      Future<void> show(GameState game) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionNotifications(game: game, child: const SizedBox()),
          ),
        ),
      );
      await show(const GameState());
      await show(
        const GameState(
          players: {'p': Player(id: 'p', name: 'Ada')},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ada verbunden.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await show(
        const GameState(
          players: {'p': Player(id: 'p', name: 'Ada', isConnected: false)},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ada getrennt.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await show(
        const GameState(
          allAnswersRevision: 1,
          players: {'p': Player(id: 'p', name: 'Ada', isConnected: false)},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Alle Spieler / teilnehmenden Teams haben geantwortet.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'final placement uses tied team scores and only opens once per game',
    (tester) async {
      const game = GameState(
        isFinished: true,
        mode: TeamMode(),
        players: {
          'p': Player(id: 'p', name: 'Ada', teamId: 'a'),
          'q': Player(id: 'q', name: 'Bob', teamId: 'b'),
          'r': Player(id: 'r', name: 'Cleo', teamId: 'c'),
        },
        scores: ScoreState(byPlayer: {'p': 20, 'q': 30, 'r': 20}),
      );
      Future<void> show(GameState game) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionNotifications(
              game: game,
              playerId: 'p',
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await show(game);
      await tester.pumpAndSettle();
      expect(
        find.text('Dein Team erreicht Platz 2 mit 20 Punkten!'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await show(game.copyWith(hostTimeMicros: 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
