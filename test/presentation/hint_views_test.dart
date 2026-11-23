/// Hints on the host, the player devices, the TV and in the editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/question_editor.dart';
import 'package:quizmo/presentation/quizmaster/game_sections.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

import '../core/simulation/preview_session_test.dart' show simulationQuiz;

const question = TrueFalseQuestion(
  id: 'q1',
  prompt: 'One?',
  correctAnswer: true,
  timeLimit: Duration.zero,
  hints: [
    QuestionHint(text: 'Alpha hint', cost: 2),
    QuestionHint(text: 'Beta hint'),
  ],
);

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppLocalizations.delegate],
  theme: QuizmoApp.buildTheme(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the host shows hints one by one and takes the last one back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = QuizEngineBloc(questionBank: const [question]);
    addTearDown(engine.close);
    engine
      ..add(const StartGameEvent())
      ..add(const StartRoundEvent('q1'));
    await tester.pumpWidget(
      app(
        BlocBuilder<QuizEngineBloc, QuizEngineState>(
          bloc: engine,
          builder: (context, state) => SingleChildScrollView(
            child: buildGameSections(
              context,
              engine: engine,
              engineState: state,
              quizName: 'Quiz',
            )[DashboardSection.liveRound],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha hint'), findsOneWidget);
    expect(
      find.text('Hints: 0 of 2 · next hint: −2 points · up to 10 points left'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('take-back-hint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('show-hint')));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.shownHintCount, 1);
    expect(
      find.text('Hints: 1 of 2 · next hint: free · up to 8 points left'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('show-hint')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('show-hint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('take-back-hint')));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.shownHintCount, 1);
  });

  testWidgets('players see a hint as soon as the host shows it', (
    tester,
  ) async {
    final session = PreviewSession(simulationQuiz(questions: const [question]));
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
      app(BlocProvider.value(value: player, child: const LocalPlayerBoard())),
    );
    session.send(const StartGameEvent());
    session.send(const StartRoundEvent('q1'));
    await tester.runAsync(session.flush);
    await tester.pumpAndSettle();
    expect(find.textContaining('Hints: 0 of 2'), findsOneWidget);
    expect(find.text('Alpha hint'), findsNothing);
    session.send(const ShowHintEvent(questionId: 'q1', shownHints: 0));
    await tester.runAsync(session.flush);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alpha hint'), findsOneWidget);
    expect(find.text('Beta hint'), findsNothing);
    expect(find.text('New hint!'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('the TV shows long hints without overflowing', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = 'A long hint that needs more than one line. ' * 8;
    const media = [CodeAttachment(code: 'secret hint code', language: 'dart')];
    final current = MultipleChoiceQuestion(
      id: 'q',
      prompt: 'A rather long question prompt for the big screen. ' * 5,
      options: [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
          AnswerOption(id: id, label: 'Option $id'),
      ],
      correctOptionId: 'a',
      hints: [
        for (var i = 0; i < 4; i++)
          QuestionHint(text: '$i $long', cost: 1, media: i == 2 ? media : []),
        const QuestionHint(text: 'Concealed'),
      ],
    );
    Future<void> show(List<int> times, RoundStatus status) async {
      await tester.pumpWidget(
        app(
          TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: GameState(
                round: RoundState(
                  question: current,
                  status: status,
                  startedAtHostMicros: 1,
                  hintTimesMicros: times,
                ),
              ).redactedForPlayers(),
              snapshotReceivedAt: DateTime.now(),
            ),
            joinUri: Uri.parse('http://192.168.1.42:8080'),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }

    await show(const [], RoundStatus.acceptingAnswers);
    expect(find.textContaining('Hints: 0 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-hints')), findsNothing);
    await show(const [1, 2, 3, 4], RoundStatus.acceptingAnswers);
    // At most the last three hints fit on the canvas.
    expect(find.textContaining('Hint 1 ('), findsNothing);
    expect(find.textContaining('Hint 2 ('), findsOneWidget);
    expect(find.textContaining('Hint 4 ('), findsOneWidget);
    expect(find.textContaining('Concealed'), findsNothing);
    expect(find.byKey(const ValueKey('hint-media-2')), findsOneWidget);
    await show(const [1, 2, 3, 4], RoundStatus.revealed);
    expect(find.byKey(const ValueKey('tv-hints')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('editor', () {
    Future<Question?> Function() open(
      WidgetTester tester,
      Question question,
      QuizFormat format,
    ) {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Question? saved;
      return () async {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async => saved = await Navigator.of(context)
                    .push<Question>(
                      MaterialPageRoute(
                        builder: (_) => QuestionEditorPage(
                          question: question,
                          format: format,
                        ),
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return saved;
      };
    }

    testWidgets('adds a hint with text and deduction', (tester) async {
      Question? saved;
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  saved = await Navigator.of(context).push<Question>(
                    MaterialPageRoute(
                      builder: (_) => const QuestionEditorPage(
                        question: question,
                        format: StandardFormat(),
                      ),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-hint')));
      await tester.pumpAndSettle();
      FilledButton save() =>
          tester.widget<FilledButton>(find.byKey(const ValueKey('save-hint')));
      expect(save().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('hint-text')),
        'Gamma hint',
      );
      await tester.enterText(find.byKey(const ValueKey('hint-cost')), '-3');
      await tester.pump();
      expect(save().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('hint-cost')), '3');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-hint')));
      await tester.pumpAndSettle();
      // Move the new hint up, then save the question.
      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save question'));
      await tester.pumpAndSettle();
      expect(saved!.hints.map((h) => (h.text, h.cost)), [
        ('Alpha hint', 2),
        ('Gamma hint', 3),
        ('Beta hint', 0),
      ]);
    });

    testWidgets('says that poker hints are free', (tester) async {
      await open(tester, question, const PokerFormat())();
      expect(
        find.text('In the poker chips format hints are always free.'),
        findsOneWidget,
      );
      expect(find.textContaining('−2 points'), findsNothing);
    });
  });
}
