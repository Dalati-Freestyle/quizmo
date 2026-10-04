import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';

void main() {
  testWidgets('editor saves poker format with configurable starting chips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryQuizRepository();
    final quiz = Quiz(
      id: 'quiz',
      name: 'Poker',
      description: 'Test',
      category: 'Test',
      teams: const [Team(id: 'a', name: 'A')],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QuizEditorPage(
          repository: repository,
          quiz: quiz,
          createId: () => 'new',
        ),
      ),
    );
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokerchips').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '250');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokerchips').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save quiz'));
    await tester.pumpAndSettle();
    expect(
      (await repository.loadAll()).single.format,
      const PokerFormat(startingChips: 250),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile wager view validates balance and supports all-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bets = <int>[];
    final game = GameState(
      players: const {'p': Player(id: 'p', name: 'Player', teamId: 'a')},
      teams: const {'a': Team(id: 'a', name: 'A')},
      round: const RoundState(
        question: TrueFalseQuestion(id: 'q', prompt: 'True?'),
      ),
      poker: PokerState.start(100, ['a']).copyWith(betting: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PokerWagerView(
            state: PlayerSessionState(game: game, playerId: 'p'),
            onWager: bets.add,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '101');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '20');
    await tester.pump();
    await tester.tap(find.text('Teameinsatz bestätigen'));
    await tester.tap(find.text('All-in'));
    expect(bets, [20, 100]);
    expect(tester.takeException(), isNull);
  });
}
