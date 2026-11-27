import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/grading_dialog.dart';
import 'package:quizmo/presentation/common/question_result_view.dart';
import 'package:quizmo/presentation/common/session_notifications.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';
import 'package:quizmo/presentation/quizmaster/editor/question_editor.dart';

const question = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Hauptstadt?',
  acceptedAnswers: ['Berlin'],
  manualGrading: true,
);

void main() {
  testWidgets(
    'host reviews every answer and final feedback uses host verdicts',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = QuizEngineBloc(
        questionBank: const [question],
        now: () => 1000000,
      );
      addTearDown(engine.close);
      Future<void> send(QuizEngineEvent event) async {
        engine.add(event);
        await tester.pump();
      }

      for (final id in ['a', 'b']) {
        await send(PlayerJoinedEvent(Player(id: id, name: 'Spieler $id')));
      }
      await send(const StartRoundEvent('q'));
      for (final id in ['a', 'b']) {
        await send(
          SubmitAnswerEvent(
            ShortAnswer(
              playerId: id,
              questionId: 'q',
              clientTimestampMicros: 1100000,
              clockOffsetMicros: 0,
              text: id == 'a' ? 'Berlin' : 'Berln',
            ),
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GradingHost(
              engine: engine,
              child: SingleChildScrollView(
                child: BlocBuilder<QuizEngineBloc, QuizEngineState>(
                  bloc: engine,
                  builder: (context, state) => LiveRoundPanel(
                    state: state,
                    onJudge: (_) {},
                    onReveal: () => engine.add(const RevealRoundEvent()),
                    onLock: () {},
                    onNext: () {},
                    onCloseRound: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Opens by itself: everybody answered, the round is closed.
      expect(find.byType(GradingDialog), findsOneWidget);
      expect(find.text('Musterlösung: Berlin'), findsOneWidget);
      expect(find.text('Empfehlung: Passt zur Lösung.'), findsOneWidget);
      expect(
        find.text('Empfehlung: Fast richtig, vermutlich ein Tippfehler.'),
        findsOneWidget,
      );
      FilledButton confirm() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-grades')),
      );
      expect(confirm().onPressed, isNull, reason: 'nothing is preselected');
      expect(find.text('Bestätigen (noch 2)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('grade-a-true')));
      await tester.pumpAndSettle();
      expect(find.text('1 von 2 bewertet'), findsOneWidget);

      // Closing judges nothing and keeps the choice.
      await tester.tap(find.text('Später'));
      await tester.pumpAndSettle();
      expect(find.byType(GradingDialog), findsNothing);
      expect(engine.state.game.round.answerVerdicts, isEmpty);
      engine.add(const PlayerJoinedEvent(Player(id: 'c', name: 'Spät')));
      await tester.pumpAndSettle();
      expect(find.byType(GradingDialog), findsNothing, reason: 'opens once');
      await tester.ensureVisible(find.byKey(const ValueKey('open-grading')));
      await tester.tap(find.byKey(const ValueKey('open-grading')));
      await tester.pumpAndSettle();
      expect(find.text('1 von 2 bewertet'), findsOneWidget);

      // Every choice can be changed until the confirmation.
      await tester.tap(find.byKey(const ValueKey('grade-a-false')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accept-recommendations')));
      await tester.pumpAndSettle();
      expect(find.text('2 von 2 bewertet'), findsOneWidget);
      expect(engine.state.game.scores.history, isEmpty);
      expect(engine.state.game.corrections, isEmpty);
      await tester.tap(find.byKey(const ValueKey('confirm-grades')));
      await tester.pumpAndSettle();
      expect(engine.state.game.round.answerVerdicts, {'a': 0, 'b': 1});
      expect(engine.state.game.corrections, hasLength(2));
      expect(find.byType(GradingDialog), findsNothing);
      expect(engine.state.game.scores.scoreOf('a'), 0);
      expect(engine.state.game.scores.scoreOf('b'), 10);
      expect(roundFeedback(engine.state.game, 'a'), contains('Leider falsch'));
      expect(roundFeedback(engine.state.game, 'b'), contains('Richtig!'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, size, scale) in [
    ('phone', const Size(360, 640), 1.0),
    ('phone with large text', const Size(320, 568), 2.0),
    ('phone in landscape', const Size(640, 340), 1.0),
    ('desktop', const Size(1400, 900), 1.0),
  ]) {
    testWidgets('the pop-up fits on a $name with many teams', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final teams = {
        for (var i = 0; i < 12; i++) 't$i': Team(id: 't$i', name: 'Team $i'),
      };
      final engine = QuizEngineBloc(
        questionBank: const [question],
        teams: teams,
        mode: const TeamMode(),
        now: () => 1000000,
      );
      addTearDown(engine.close);
      for (final id in teams.keys) {
        engine.add(
          PlayerJoinedEvent(Player(id: 'p$id', name: 'P $id', teamId: id)),
        );
      }
      engine.add(const StartRoundEvent('q'));
      for (final id in teams.keys.skip(1)) {
        engine.add(
          SubmitAnswerEvent(
            ShortAnswer(
              playerId: 'p$id',
              questionId: 'q',
              clientTimestampMicros: 1100000,
              clockOffsetMicros: 0,
              text: 'lange Antwort ' * 20,
            ),
          ),
        );
      }
      engine.add(const RevealRoundEvent());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GradingHost(engine: engine, child: const SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GradingDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('grading-t0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Escape and the barrier judge nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(GradingDialog), findsNothing);
      expect(engine.state.game.round.answerVerdicts, isEmpty);
    });
  }

  for (final format in [
    const StandardFormat(),
    const PokerFormat(),
    const JeopardyFormat(JeopardyBoard(rowPoints: [100], categories: [])),
  ]) {
    for (final manual in [true, false]) {
      testWidgets('editor saves manual grading=$manual for ${format.label}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ShortAnswerQuestion? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<ShortAnswerQuestion>(
                    MaterialPageRoute(
                      builder: (_) => QuestionEditorPage(
                        question: ShortAnswerQuestion(
                          id: 'q',
                          prompt: 'Hauptstadt?',
                          acceptedAnswers: ['Berlin'],
                          manualGrading: !manual,
                        ),
                        format: format,
                      ),
                    ),
                  );
                },
                child: const Text('Editor'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Editor'));
        await tester.pumpAndSettle();
        final grading = find.byType(DropdownButtonFormField<bool>);
        await tester.ensureVisible(grading);
        await tester.tap(grading);
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(manual ? 'Manuell durch den Spielleiter' : 'Automatisch')
              .last,
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('nur für die Empfehlung'),
          manual ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Save question'));
        await tester.pumpAndSettle();
        expect(saved?.manualGrading, manual);
        expect(saved?.acceptedAnswers, ['Berlin']);
        expect(saved?.maxEdits, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('player and TV show no recommendation or verdict before reveal', (
    tester,
  ) async {
    const answer = ShortAnswer(
      playerId: 'a',
      questionId: 'q',
      clientTimestampMicros: 1,
      clockOffsetMicros: 0,
      text: 'Hamburg',
    );
    const game = GameState(
      round: RoundState(
        question: question,
        status: RoundStatus.locked,
        answers: {'a': answer},
        answerVerdicts: {'a': 1},
      ),
    );
    final hidden = game.redactedForPlayers();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionResultView(
            question: hidden.round.question!,
            game: hidden,
          ),
        ),
      ),
    );
    expect(
      find.text('Der Spielleiter bewertet die Antworten.'),
      findsOneWidget,
    );
    expect(find.textContaining('Empfehlung'), findsNothing);
    expect(find.textContaining('Lösung:'), findsNothing);
    expect(find.text('Richtig'), findsNothing);
    final revealed = game
        .copyWith(round: game.round.copyWith(status: RoundStatus.revealed))
        .redactedForPlayers();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionResultView(
            question: revealed.round.question!,
            game: revealed,
          ),
        ),
      ),
    );
    expect(find.text('Richtig'), findsOneWidget);
    expect(find.text('Lösung: Berlin'), findsOneWidget);
    expect(find.textContaining('Empfehlung'), findsNothing);
  });
}
