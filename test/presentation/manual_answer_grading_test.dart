import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
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
            body: SingleChildScrollView(
              child: BlocBuilder<QuizEngineBloc, QuizEngineState>(
                bloc: engine,
                builder: (context, state) => LiveRoundPanel(
                  state: state,
                  onJudge: (_) {},
                  onJudgeAnswer: engine.add,
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
      expect(find.text('Empfehlung: Passt zur Lösung.'), findsOneWidget);
      expect(
        find.text('Empfehlung: Fast richtig, vermutlich ein Tippfehler.'),
        findsOneWidget,
      );
      final finish = find.widgetWithText(FilledButton, 'Bewertung abschließen');
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);

      Finder grade(String id, String label) => find.descendant(
        of: find.byKey(ValueKey('manual-answer-$id')),
        matching: find.widgetWithText(ChoiceChip, label),
      );
      await tester.ensureVisible(grade('a', 'Wrong'));
      await tester.tap(grade('a', 'Wrong'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(grade('b', 'Richtig'));
      await tester.tap(grade('b', 'Richtig'));
      await tester.pumpAndSettle();
      expect(engine.state.game.round.answerVerdicts, {'a': 0, 'b': 1});
      expect(find.text('Noch 0 Antworten zu bewerten'), findsOneWidget);
      expect(engine.state.game.scores.history, isEmpty);
      await tester.ensureVisible(finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(engine.state.game.scores.scoreOf('a'), 0);
      expect(engine.state.game.scores.scoreOf('b'), 10);
      expect(roundFeedback(engine.state.game, 'a'), contains('Leider falsch'));
      expect(roundFeedback(engine.state.game, 'b'), contains('Richtig!'));
      expect(tester.takeException(), isNull);
    },
  );

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
