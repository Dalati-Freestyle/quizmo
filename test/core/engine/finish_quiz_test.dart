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

    test('an early end cancels the running round without scoring', () async {
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
      // A second player keeps the round open (no auto reveal).
      await send(const PlayerJoinedEvent(Player(id: 'o', name: 'O')));
      await send(const StartGameEvent());
      await send(const StartRoundEvent('q1'));
      await send(
        const SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: 'p',
            questionId: 'q1',
            clientTimestampMicros: 1700000000000000,
            clockOffsetMicros: 0,
            value: true,
          ),
        ),
      );
      // Without the flag the host cannot end a game with open questions.
      await send(const FinishQuizEvent());
      expect(engine.state.game.isFinished, isFalse);
      await send(const FinishQuizEvent(early: true));
      final game = engine.state.game;
      expect(game.isFinished, isTrue);
      expect(game.round.question, isNull);
      expect(game.completedQuestionIds, isEmpty);
      expect(game.scores.scoreOf('p'), 0);
    });

    test('an early end returns reserved poker stakes', () async {
      engine = QuizEngineBloc(
        questionBank: _bank,
        teams: const {'a': Team(id: 'a', name: 'A')},
        mode: const TeamMode(),
        pokerStartingChips: 100,
        now: () => 1700000000000000,
      );
      addTearDown(engine.close);
      await send(
        const PlayerJoinedEvent(Player(id: 'p', name: 'P', teamId: 'a')),
      );
      await send(const StartGameEvent());
      await send(const StartRoundEvent('q1'));
      await send(
        const PlacePokerWagerEvent(playerId: 'p', questionId: 'q1', wager: 30),
      );
      expect(engine.state.game.poker!.chips['a'], 70);
      await send(const FinishQuizEvent(early: true));
      expect(engine.state.game.poker!.chips['a'], 100);
      expect(engine.state.game.poker!.wagers, isEmpty);
    });
  });

  testWidgets('ending early asks for a confirmation first', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveRoundPanel(
              state: const QuizEngineState(
                game: GameState(
                  questionBank: [
                    TrueFalseQuestion(id: 'q', prompt: 'Q?'),
                    TrueFalseQuestion(id: 'r', prompt: 'R?'),
                  ],
                  isStarted: true,
                  round: RoundState(
                    question: TrueFalseQuestion(id: 'q', prompt: 'Q?'),
                    status: RoundStatus.acceptingAnswers,
                  ),
                ),
              ),
              onJudge: (_) {},
              onReveal: () {},
              onLock: () {},
              onNext: () {},
              onCloseRound: () {},
              onFinishEarly: () => finished = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('finish-quiz-early')));
    await tester.pumpAndSettle();
    expect(find.textContaining('abgebrochen'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(finished, isFalse);
    await tester.tap(find.byKey(const ValueKey('finish-quiz-early')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-finish-early')));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
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
