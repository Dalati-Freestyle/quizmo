/// The quiz preview must show exactly what a real game shows: the same
/// player view (incl. final page and protocol download) and the same admin
/// sections. These tests guard the shared widgets against drifting apart.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/player/player_final_page.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/game_sections.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout.dart';

import '../core/simulation/preview_session_test.dart' show simulationQuiz;

const _questions = [
  TrueFalseQuestion(id: 'q1', prompt: 'One?', correctAnswer: true),
  TrueFalseQuestion(id: 'q2', prompt: 'Two?', correctAnswer: true),
];

void main() {
  testWidgets(
    'an early end shows the final page with download in the preview player',
    (tester) async {
      final session = PreviewSession(simulationQuiz(questions: _questions));
      addTearDown(session.close);
      final id = session.addParticipant(name: 'Manual');
      await tester.runAsync(session.flush);
      final player = PlayerSessionCubit.local(
        playerId: id,
        initialGame: session.guestGame,
        snapshots: session.guestSnapshots,
        send: session.send,
        now: () => session.clock.nowMicros,
      );
      addTearDown(player.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: BlocProvider.value(
              value: player,
              child: const LocalPlayerBoard(),
            ),
          ),
        ),
      );
      session.send(const StartGameEvent());
      session.send(const StartRoundEvent('q1'));
      session.send(const FinishQuizEvent(early: true));
      await tester.runAsync(session.flush);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(session.guestGame.protocol, isNotNull);
      expect(find.byType(PlayerFinalPage), findsOneWidget);
      // The placement pop-up fades out by itself, as on a real device.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    },
  );

  test('preview and dashboard never build game panels on their own', () {
    for (final path in [
      'lib/presentation/quizmaster/preview/quiz_preview_page.dart',
      'lib/presentation/quizmaster/host_dashboard_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('buildGameSections('), reason: path);
      for (final panel in [
        'LiveRoundPanel(',
        'QuestionBankPanel(',
        'JeopardyBoardPanel(',
        'PlayersPanel(',
        'ScoreboardView(',
        'CorrectionHistoryPanel(',
      ]) {
        expect(
          source,
          isNot(contains(panel)),
          reason: '$path must use buildGameSections instead of $panel',
        );
      }
    }
    final preview = File(
      'lib/presentation/quizmaster/preview/quiz_preview_page.dart',
    ).readAsStringSync();
    expect(preview, contains('TvScreen('));
    expect(preview, contains('LocalPlayerBoard('));
  });

  testWidgets('the preview and the dashboard share every game section', (
    tester,
  ) async {
    final engine = QuizEngineBloc(questionBank: _questions);
    addTearDown(engine.close);
    late Map<DashboardSection, Widget> sections;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Builder(
          builder: (context) {
            sections = buildGameSections(
              context,
              engine: engine,
              engineState: engine.state,
              quizName: 'Quiz',
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      sections.keys,
      containsAll(<DashboardSection>{
        DashboardSection.startQuiz,
        DashboardSection.liveRound,
        DashboardSection.questions,
        DashboardSection.scoreboard,
        DashboardSection.corrections,
        DashboardSection.players,
      }),
    );
  });
}
