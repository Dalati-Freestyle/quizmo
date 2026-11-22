/// TV stages for the poker category phase and for interstitial slides.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

void main() {
  Future<void> show(WidgetTester tester, GameState game) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: QuizmoApp.buildTheme(Brightness.dark),
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: game.redactedForPlayers(),
              snapshotReceivedAt: DateTime.now(),
            ),
            joinUri: Uri.parse('http://192.168.1.42:8080'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  const teams = {
    'a': Team(id: 'a', name: 'Alpha'),
    'b': Team(id: 'b', name: 'Beta'),
  };

  testWidgets('the category phase hides the question on the TV', (
    tester,
  ) async {
    final game = GameState(
      mode: const TeamMode(),
      teams: teams,
      round: const RoundState(
        question: TrueFalseQuestion(
          id: 'q',
          prompt: 'Secret question?',
          category: 'Deutschland',
        ),
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: 1,
      ),
      poker: PokerState.start(15, teams.keys).copyWith(
        betting: true,
        questionHidden: true,
        category: 'Deutschland',
        wagers: {'b': 3},
      ),
      jokers: const JokerState(jokers: [ForcedStakeJoker()]).withPlay(
        const JokerPlay(
          jokerId: 'forcedStake',
          teamId: 'a',
          targetTeamId: 'b',
          paidChips: 2,
        ),
      ),
    );
    await show(tester, game);
    expect(find.text('Next category'), findsOneWidget);
    expect(find.text('Deutschland'), findsOneWidget);
    expect(find.text('Secret question?'), findsNothing);
    expect(
      find.text('Alpha attacks Beta: forced stake of 3 chips.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an interstitial slide replaces the lobby', (tester) async {
    const game = GameState(
      activeSlide: InfoSlide(id: 's', title: 'Trinkpause', text: 'Prost!'),
    );
    await show(tester, game);
    expect(find.text('Trinkpause'), findsOneWidget);
    expect(find.text('Prost!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
