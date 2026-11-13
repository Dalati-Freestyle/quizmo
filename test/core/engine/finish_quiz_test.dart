import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';

const _bank = [
  TrueFalseQuestion(id: 'q1', prompt: 'One?', correctAnswer: true),
  TrueFalseQuestion(id: 'q2', prompt: 'Two?', correctAnswer: true),
];

void main() {
  late QuizEngineBloc engine;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  setUp(() {
    engine = QuizEngineBloc(questionBank: _bank, now: () => 1700000000000000);
    addTearDown(engine.close);
  });

  group('FinishQuizEvent', () {
    test('the last reveal waits for the host to finish the game', () async {
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
      await send(const StartRoundEvent('q1'));
      await send(const RevealRoundEvent());
      expect(engine.state.game.canFinish, isFalse);
      await send(const FinishQuizEvent());
      expect(engine.state.game.isFinished, isFalse);
      expect(engine.state.notice, 'Das Quiz kann noch nicht beendet werden.');

      await send(const StartRoundEvent('q2'));
      expect(engine.state.game.canFinish, isFalse);
      await send(const RevealRoundEvent());
      final game = engine.state.game;
      expect(game.allQuestionsPlayed, isTrue);
      expect(game.isFinished, isFalse);
      expect(game.round.status, RoundStatus.revealed);
      // Guests keep the solution of the last question and get no protocol.
      expect(guestSnapshotOf(game, title: 'Quiz').protocol, isNull);
      expect(guestSnapshotOf(game, title: 'Quiz').round.question?.id, 'q2');

      await send(const FinishQuizEvent());
      expect(engine.state.game.isFinished, isTrue);
      expect(engine.state.game.canFinish, isFalse);
      expect(
        guestSnapshotOf(engine.state.game, title: 'Quiz').protocol,
        isNotNull,
      );
    });

    test('a reset starts over without the finished flag', () async {
      await send(const StartRoundEvent('q1'));
      await send(const RevealRoundEvent());
      await send(const StartRoundEvent('q2'));
      await send(const RevealRoundEvent());
      await send(const FinishQuizEvent());
      await send(const ResetGameEvent());
      expect(engine.state.game.isFinished, isFalse);
      expect(engine.state.game.allQuestionsPlayed, isFalse);
    });
  });

  testWidgets('the round panel offers to finish the quiz', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveRoundPanel(
              state: const QuizEngineState(
                game: GameState(
                  questionBank: [TrueFalseQuestion(id: 'q', prompt: 'Q?')],
                  completedQuestionIds: {'q'},
                  isStarted: true,
                  round: RoundState(
                    question: TrueFalseQuestion(id: 'q', prompt: 'Q?'),
                    status: RoundStatus.revealed,
                  ),
                ),
              ),
              onJudge: (_) {},
              onReveal: () {},
              onLock: () {},
              onNext: () => fail('There is no next question.'),
              onCloseRound: () {},
              onFinish: () => finished = true,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('finish-quiz')));
    await tester.tap(find.byKey(const ValueKey('finish-quiz')));
    expect(finished, isTrue);
  });
}
