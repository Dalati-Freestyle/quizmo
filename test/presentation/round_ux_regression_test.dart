import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/spectator/animated_score_value.dart';

void main() {
  testWidgets(
    'wager defaults to TV budget and remains editable after confirmation',
    (tester) async {
      final wagers = <int>[];
      var poker = PokerState.start(250, ['a']).copyWith(betting: true);
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PokerWagerView(
              state: PlayerSessionState(
                playerId: 'p',
                game: GameState(
                  totalQuestionCount: 12,
                  players: const {'p': Player(id: 'p', name: 'P', teamId: 'a')},
                  teams: const {'a': Team(id: 'a', name: 'A')},
                  round: const RoundState(
                    question: TrueFalseQuestion(
                      id: 'q',
                      prompt: 'Full question',
                    ),
                  ),
                  poker: poker,
                ),
              ),
              onWager: wagers.add,
            ),
          ),
        ),
      );
      await pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '20',
      );
      await tester.tap(find.text('Teameinsatz bestätigen'));
      expect(wagers, [20]);
      poker = poker.copyWith(chips: {'a': 230}, wagers: {'a': 20});
      await pump();
      await tester.enterText(find.byType(TextField), '40');
      await tester.pump();
      await tester.tap(find.text('Teameinsatz ändern'));
      expect(wagers, [20, 40]);
      expect(find.text('Full question'), findsOneWidget);
      poker = poker.copyWith(chips: {'a': 210}, wagers: {'a': 40});
      await pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '40',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Daily Double default follows a changed score cap', (
    tester,
  ) async {
    Future<void> pump(int max) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyDoubleWagerView(maxWager: max, onWager: (_) {}),
        ),
      ),
    );
    await pump(200);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '200',
    );
    await pump(450);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '450',
    );
  });

  testWidgets('score gain counts up and celebrates only the gain', (
    tester,
  ) async {
    Future<void> pump(int points) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: AnimatedScoreValue(points: points)),
        ),
      ),
    );
    await pump(100);
    expect(find.text('100'), findsOneWidget);
    await pump(150);
    expect(find.text('✦ +50'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    final numbers = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => int.tryParse(text.data ?? ''))
        .whereType<int>();
    expect(numbers.single, allOf(greaterThan(100), lessThan(150)));
    await tester.pumpAndSettle();
    expect(find.text('150'), findsOneWidget);
    expect(find.text('✦ +50'), findsNothing);
    await pump(130);
    expect(find.textContaining('✦'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('130'), findsOneWidget);
  });
}
