/// Feedback from the game night: distinct host cards, persistent button
/// feedback for players, the on-turn pick on the TV, a board that shrinks on
/// phones and a near-fullscreen picture zoom.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/quizmaster/grading_dialog.dart';
import 'package:quizmo/presentation/common/jeopardy_board_view.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/player/questions/new_question_views.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

const mc = MultipleChoiceQuestion(
  id: 'mc',
  prompt: 'Which hero carries the shield?',
  options: [
    AnswerOption(id: 'a', label: 'Thor'),
    AnswerOption(id: 'b', label: 'Captain America'),
  ],
  correctOptionId: 'b',
  adminNotes: 'Mention the vibranium.',
  // No round timer that would outlive the test.
  timeLimit: Duration.zero,
);

void main() {
  Widget panel(QuizEngineBloc engine) => MaterialApp(
    home: Scaffold(
      body: GradingHost(
        engine: engine,
        child: SingleChildScrollView(
          child: BlocBuilder<QuizEngineBloc, QuizEngineState>(
            bloc: engine,
            builder: (context, state) => LiveRoundPanel(
              state: state,
              onJudge: (_) {},
              onSetVerbalAnswers: (enabled) =>
                  engine.add(SetVerbalAnswersEvent(enabled)),
              onReveal: () => engine.add(const RevealRoundEvent()),
              onLock: () {},
              onNext: () {},
              onCloseRound: () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('host sees note, solution and answers as separate cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = QuizEngineBloc(questionBank: const [mc], now: () => 1000);
    addTearDown(engine.close);
    engine
      ..add(const StartGameEvent())
      ..add(const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada')))
      ..add(const PlayerJoinedEvent(Player(id: 'p2', name: 'Linus')));
    await tester.pumpWidget(panel(engine));
    await tester.pumpAndSettle();

    Finder inCard(String card, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('round-card-$card')),
      matching: matching,
    );
    expect(inCard('answers', find.text('Keine Frage aktiv.')), findsOneWidget);

    engine.add(const StartRoundEvent('mc'));
    await tester.pumpAndSettle();
    expect(inCard('note', find.text('Mention the vibranium.')), findsOneWidget);
    expect(inCard('solution', find.text('Captain America')), findsOneWidget);
    expect(
      inCard('answers', find.text('Warte auf Antworten der Spieler…')),
      findsOneWidget,
    );
    // The solution is not repeated among the answers or the note.
    expect(inCard('note', find.text('Captain America')), findsNothing);

    engine.add(
      const SubmitAnswerEvent(
        MultipleChoiceAnswer(
          playerId: 'p1',
          questionId: 'mc',
          clientTimestampMicros: 1000,
          clockOffsetMicros: 0,
          optionId: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      inCard('answers', find.byKey(const ValueKey('host-answer-p1'))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('verbal mode lets the host accept an answer nobody typed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = QuizEngineBloc(questionBank: const [mc], now: () => 1000);
    addTearDown(engine.close);
    engine
      ..add(const StartGameEvent())
      ..add(const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada')));
    await tester.pumpWidget(panel(engine));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('verbal-answers-switch')));
    await tester.pumpAndSettle();
    expect(engine.state.game.verbalAnswers, isTrue);
    engine.add(const StartRoundEvent('mc'));
    await tester.pumpAndSettle();

    // Closing the answers opens the pop-up; judging nobody is possible too.
    final close = find.text('Antworten schließen & bewerten');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('grading-p1'));
    expect(
      find.descendant(
        of: row,
        matching: find.text('Nichts eingetippt (mündliche Antwort)'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('grade-p1-true')));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.answerVerdicts, isEmpty);
    await tester.tap(find.byKey(const ValueKey('confirm-grades')));
    await tester.pumpAndSettle();
    expect(engine.state.game.round.answerVerdicts, {'p1': 1});
    expect(engine.state.game.round.answers['p1'], isA<VerbalAnswer>());
    expect(engine.state.game.round.status, RoundStatus.revealed);
    expect(find.byType(GradingDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pressed answer button stays coloured', (tester) async {
    bool? sent;
    var submitted = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return TrueFalseQuestionView(
                question: const TrueFalseQuestion(id: 't', prompt: 'Thor?'),
                enabled: !submitted,
                submitted: submitted,
                onSubmit: (value) => sent = value,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('true-false-true')));
    rebuild(() => submitted = true);
    await tester.pump();
    expect(sent, isTrue);
    final chosen = find.byKey(const ValueKey('true-false-true'));
    expect(
      find.descendant(of: chosen, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('true-false-false')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnswerSubmitButton(label: 'Send', sent: true, onPressed: null),
        ),
      ),
    );
    expect(find.text('Gesendet'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
  });

  group('Jeopardy board on a phone', () {
    final board = JeopardyBoard(
      rowPoints: const [100, 200],
      categories: [
        for (var i = 0; i < 6; i++)
          JeopardyCategory(
            name: 'Category $i',
            cells: [
              JeopardyCell(questionId: 'q$i-1'),
              JeopardyCell(questionId: 'q$i-2'),
            ],
          ),
      ],
    );

    Future<void> pumpAt(WidgetTester tester, double width) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: JeopardyBoardView(
                board: board,
                completedQuestionIds: const {},
                pendingQuestionId: 'q0-1',
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('shrinks to fit instead of scrolling', (tester) async {
      // Six columns need 552 px; a phone has less.
      await pumpAt(tester, 360);
      final scaled = find.byKey(const ValueKey('jeopardy-board-scaled'));
      expect(scaled, findsOneWidget);
      expect(tester.getSize(scaled).width, closeTo(360, 0.5));
      expect(find.byType(SingleChildScrollView), findsNothing);
      // The pick waiting for the host is marked.
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls only below the readable minimum', (tester) async {
      await pumpAt(tester, 200);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the TV shows what the player on turn picked', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = QuizEngineBloc(
      questionBank: const [mc],
      // Answers of teams stay secret: they may still be replaced.
      jeopardyBoard: const JeopardyBoard(
        rowPoints: [100],
        categories: [
          JeopardyCategory(
            name: 'Heroes',
            cells: [JeopardyCell(questionId: 'mc')],
          ),
        ],
      ),
      now: () => 1000,
    );
    addTearDown(engine.close);
    engine
      ..add(const StartGameEvent())
      ..add(const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada')))
      ..add(const PlayerJoinedEvent(Player(id: 'p2', name: 'Linus')))
      // Judged by the host, so the round stays open after the pick.
      ..add(const SetVerbalAnswersEvent(true))
      ..add(const SelectJeopardyCellEvent('mc'));
    await tester.runAsync(() => pumpEventQueue());
    final turn = engine.state.game.jeopardy!.currentTeamId!;
    engine.add(
      SubmitAnswerEvent(
        MultipleChoiceAnswer(
          playerId: turn,
          questionId: 'mc',
          clientTimestampMicros: 1000,
          clockOffsetMicros: 0,
          optionId: 'a',
        ),
      ),
    );
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: engine.state.game.redactedForPlayers(),
            ),
            joinUri: Uri.parse('http://localhost:8080'),
          ),
        ),
      ),
    );
    await tester.pump();
    final banner = find.byKey(const ValueKey('tv-on-turn-answer'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.textContaining('A · Thor')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture zoom uses the whole screen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asset = MediaAsset.upload(
      Uint8List.fromList(
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
          '<rect width="10" height="10" fill="red"/></svg>',
        ),
      ),
      'svg',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionMediaView(
              media: [ImageAttachment(asset: asset, zoom: true)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vergrößern'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('media-zoom-dialog'));
    expect(tester.getSize(dialog), const Size(400, 800));
    await tester.tap(find.byTooltip('Schließen'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
