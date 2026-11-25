import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/joker_play_form.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';

const teams = {
  'a': Team(id: 'a', name: 'Alpha'),
  'b': Team(id: 'b', name: 'Beta'),
};

GameState bettingGame({List<JokerPlay> plays = const []}) {
  var poker = PokerState.start(15, teams.keys).copyWith(betting: true);
  for (final play in plays) {
    if (play.targetTeamId case final target?) {
      poker = poker.copyWith(
        chips: {...poker.chips, target: 12, play.teamId: 13},
        wagers: {...poker.wagers, target: 3},
      );
    }
  }
  return GameState(
    players: const {'p': Player(id: 'p', name: 'Player', teamId: 'b')},
    teams: teams,
    round: const RoundState(
      question: TrueFalseQuestion(id: 'q', prompt: 'True?'),
    ),
    poker: poker,
    jokers: const JokerState(jokers: [CreditJoker(), ForcedStakeJoker()])
        .copyWith(plays: plays),
  );
}

void main() {
  testWidgets('a quiz gets jokers only when they are switched on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryQuizRepository();
    final quiz = Quiz(
      id: 'quiz',
      name: 'Poker',
      description: 'Test',
      category: 'Test',
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
    expect(find.text('Joker (optional)'), findsNothing);
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokerchips').last);
    await tester.pumpAndSettle();
    expect(find.text('Joker (optional)'), findsOneWidget);
    final credit = find.descendant(
      of: find.byKey(const ValueKey('joker-credit')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(credit);
    await tester.tap(credit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('credit-maxLoss')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save quiz'));
    await tester.pumpAndSettle();
    expect((await repository.loadAll()).single.jokers, const [
      CreditJoker(maxLoss: 2),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('players see their jokers and a forced stake locks the bet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PokerWagerView(
              state: PlayerSessionState(game: bettingGame(), playerId: 'p'),
              onWager: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(JokerPlayForm), findsOneWidget);
    expect(find.text('Kredit-Joker spielen (1 übrig)'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PokerWagerView(
              state: PlayerSessionState(
                game: bettingGame(
                  plays: const [
                    JokerPlay(
                      jokerId: 'forcedStake',
                      teamId: 'a',
                      targetTeamId: 'b',
                      paidChips: 2,
                    ),
                  ],
                ),
                playerId: 'p',
              ),
              onWager: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Euer Team wurde von Alpha angegriffen'),
      findsOneWidget,
    );
    expect(
      find.text('Alpha greift Beta an: Zwangseinsatz 3 Chips.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
