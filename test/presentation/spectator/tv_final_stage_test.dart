import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

GameProtocol _protocol(int teams) => GameProtocol(
  title: 'Quiz',
  generatedAtMicros: 1700000000000000,
  format: ProtocolFormat.standard,
  teamMode: true,
  standings: [
    for (var i = 0; i < teams; i++)
      ProtocolStanding(
        id: 't$i',
        name: 'Team mit einem ziemlich langen Namen $i',
        isTeam: true,
        score: 100 - i ~/ 2,
        place: i ~/ 2 * 2 + 1,
        memberIds: ['p$i'],
        memberNames: ['Spielerin $i', 'Spieler $i'],
      ),
  ],
  questions: const [],
  corrections: const [],
);

void main() {
  Future<void> pump(WidgetTester tester, GameState game) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: QuizmoApp.buildTheme(Brightness.dark),
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: game,
              snapshotReceivedAt: DateTime.now(),
            ),
            joinUri: Uri.parse('http://192.168.0.2:8080'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the finished game shows the end screen instead of a question', (
    tester,
  ) async {
    await pump(
      tester,
      GameState(
        isFinished: true,
        mode: const TeamMode(),
        protocol: _protocol(3),
      ),
    );
    expect(find.text('Final standings'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-final-t0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-final-t2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long leaderboards page through at most eight rows', (
    tester,
  ) async {
    await pump(
      tester,
      GameState(
        isFinished: true,
        mode: const TeamMode(),
        protocol: _protocol(12),
      ),
    );
    expect(find.byKey(const ValueKey('tv-final-t7')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-final-t8')), findsNothing);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(const ValueKey('tv-final-t0')), findsNothing);
    expect(find.byKey(const ValueKey('tv-final-t11')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without a protocol (game reset) the stage leaves the end', (
    tester,
  ) async {
    await pump(tester, const GameState(mode: TeamMode()));
    expect(find.text('Final standings'), findsNothing);
  });
}
