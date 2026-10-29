import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';

void main() {
  const question = BuzzerQuestion(
    id: 'q',
    prompt: 'Test',
    retryLimit: 1,
    hostEndsRound: true,
    media: [VideoAttachment(youtubeId: 'dQw4w9WgXcQ')],
  );

  testWidgets(
    'buzzer judgment includes optional reason and displayed round identity',
    (tester) async {
      JudgeBuzzerEvent? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiveRoundPanel(
                state: const QuizEngineState(
                  game: GameState(
                    players: {'p': Player(id: 'p', name: 'One')},
                    round: RoundState(
                      question: BuzzerQuestion(id: 'q', prompt: 'Test'),
                      status: RoundStatus.locked,
                      activePlayerId: 'p',
                      startedAtHostMicros: 1700000000000000,
                      resolvedAttempts: 2,
                    ),
                  ),
                ),
                onJudge: (_) =>
                    fail('The scoped judgment callback must be used.'),
                onJudgeBuzzer: (event) => received = event,
                onReveal: () {},
                onLock: () {},
                onNext: () {},
                onCloseRound: () {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Grund (optional)'),
        'Not accepted',
      );
      await tester.ensureVisible(find.text('Wrong'));
      await tester.tap(find.text('Wrong'));
      expect(received?.reason, 'Not accepted');
      expect(received?.playerId, 'p');
      expect(received?.questionId, 'q');
      expect(received?.startedAtHostMicros, 1700000000000000);
      expect(received?.resolvedAttempts, 2);
      expect(received?.wasCorrect, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retry limit suggests ending but host can reopen; media is paused',
    (tester) async {
      var reopens = 0;
      var reopensForAll = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveRoundPanel(
              state: const QuizEngineState(
                game: GameState(
                  tvMediaPaused: true,
                  round: RoundState(
                    question: question,
                    status: RoundStatus.locked,
                    resolvedAttempts: 2,
                  ),
                ),
              ),
              onJudge: (_) {},
              onReveal: () {},
              onLock: () {},
              onNext: () {},
              onCloseRound: () {},
              onReopenBuzzer: () => reopens++,
              onReopenBuzzerForAll: () => reopensForAll++,
              onEndRound: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Vorschlag: Runde beenden'), findsOneWidget);
      await tester.tap(find.text('Trotzdem Buzzer freigeben'));
      expect(reopens, 1);
      expect(reopensForAll, 0);
      await tester.tap(find.text('Buzzer für alle freigeben'));
      expect(reopensForAll, 1);
      expect(reopens, 1);
      expect(
        tester
            .widget<QuestionMediaView>(find.byType(QuestionMediaView))
            .playing,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'correct answer held for host offers ending without another attempt',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveRoundPanel(
              state: const QuizEngineState(
                game: GameState(
                  round: RoundState(
                    question: question,
                    status: RoundStatus.locked,
                    buzzerAnswerCorrect: true,
                  ),
                ),
              ),
              onJudge: (_) {},
              onReveal: () {},
              onLock: () {},
              onNext: () {},
              onCloseRound: () {},
              onReopenBuzzer: () {},
              onReopenBuzzerForAll: () {},
              onEndRound: () {},
            ),
          ),
        ),
      );
      expect(find.text('Runde beenden'), findsOneWidget);
      expect(find.textContaining('Buzzer freigeben'), findsNothing);
      expect(
        find.textContaining('Spielleiter beendet die Frage'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
