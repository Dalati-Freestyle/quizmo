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
