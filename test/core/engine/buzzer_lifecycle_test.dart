import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const board = JeopardyBoard(
  rowPoints: [100],
  allowSteal: true,
  categories: [
    JeopardyCategory(
      name: 'Test',
      cells: [JeopardyCell(questionId: 'q')],
    ),
  ],
);

void main() {
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> buzz(String id, {int timestamp = 1000000}) async {
    await send(
      BuzzerPressEvent(
        BuzzerPress(
          playerId: id,
          questionId: 'q',
          clientTimestampMicros: timestamp,
          clockOffsetMicros: 0,
        ),
      ),
    );
  }

  setUp(() {
    engine = QuizEngineBloc(
      questionBank: const [
        BuzzerQuestion(
          id: 'q',
          prompt: 'Question',
          expectedAnswer: 'Secret',
          hostEndsRound: true,
          retryLimit: 1,
          lockOutOnMiss: false,
        ),
      ],
      mode: const TeamMode(),
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      jeopardyBoard: board,
      buzzerGraceWindow: const Duration(days: 1),
      now: () => 1000000,
    );
  });
  tearDown(() => engine.close());

  Future<void> join() async {
    await send(
      const PlayerJoinedEvent(Player(id: 'a', name: 'A', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'b', name: 'B', teamId: 'b')),
    );
  }

  test(
    'joining cannot start Jeopardy; host confirms and reset restores lobby',
    () async {
      await join();
      expect(engine.state.game.mayPickQuestion('a'), isFalse);
      await send(const SelectJeopardyCellEvent('q', playerId: 'a'));
      expect(engine.state.game.jeopardy!.pendingPickQuestionId, isNull);
      expect(engine.state.game.round.question, isNull);
      await send(const StartGameEvent());
      expect(
        engine.state.game.redactedForPlayers().mayPickQuestion('a'),
        isTrue,
      );
      expect(GameState.fromJson(engine.state.game.toJson()).isStarted, isTrue);
      await send(const SelectJeopardyCellEvent('q', playerId: 'a'));
      expect(engine.state.game.jeopardy!.pendingPickQuestionId, 'q');
      await send(const ResetGameEvent());
      expect(engine.state.game.isStarted, isFalse);
      expect(engine.state.game.mayPickQuestion('a'), isFalse);
    },
  );

  test(
    'retry recommendation never reveals or prevents host continuation',
    () async {
      await join();
      await send(const SelectJeopardyCellEvent('q'));
      await buzz('a');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.roundStatus, RoundStatus.locked);
      expect(engine.state.game.jeopardy!.isStealRound, isTrue);
      expect(engine.state.game.round.resolvedAttempts, 1);
      await buzz('b');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await send(const ReopenBuzzerEvent());
      await buzz('b');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.game.round.resolvedAttempts, 2);
      expect(engine.state.game.completedQuestionIds, isEmpty);
      expect(
        engine.state.game.redactedForPlayers().round.question!.hasSolution,
        isFalse,
      );
      await send(const ReopenBuzzerEvent());
      expect(engine.state.roundStatus, RoundStatus.acceptingAnswers);
      await buzz('b');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.game.round.resolvedAttempts, 3);
      await send(const EndRoundEvent());
      expect(engine.state.roundStatus, RoundStatus.revealed);
      expect(engine.state.game.completedQuestionIds, {'q'});
    },
  );

  test('correct manual answer scores once and waits for host to end', () async {
    await join();
    await send(const SelectJeopardyCellEvent('q'));
    await buzz('a');
    await send(const LockBuzzerEvent());
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    expect(engine.state.roundStatus, RoundStatus.locked);
    expect(engine.state.game.jeopardy!.currentTeamId, 'a');
    expect(
      engine.state.game.redactedForPlayers().round.question!.hasSolution,
      isFalse,
    );
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    await send(const ReopenBuzzerEvent());
    expect(engine.state.roundStatus, RoundStatus.locked);
    expect(engine.state.game.scores.history, hasLength(1));
    await send(const EndRoundEvent());
    expect(engine.state.game.jeopardy!.currentTeamId, 'b');
    expect(
      engine.state.game.redactedForPlayers().round.question!.solutionLabel,
      'Secret',
    );
  });

  test(
    'host can reopen Jeopardy for every team, including the original picker',
    () async {
      await join();
      await send(const SelectJeopardyCellEvent('q'));
      await buzz('a');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      await send(const ReopenBuzzerEvent());
      expect(engine.state.game.mayAnswerQuestion('a'), isFalse);
      await buzz('a');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await send(const ReopenBuzzerEvent(forAll: true));
      final public = GameState.fromJson(
        engine.state.game.redactedForPlayers().toJson(),
      );
      expect(public.mayAnswerQuestion('a'), isTrue);
      expect(public.mayAnswerQuestion('b'), isTrue);
      expect(public.round.resolvedAttempts, 1);
      expect(public.tvMediaPaused, isTrue);
      expect(public.round.question!.hasSolution, isFalse);
      await buzz('a');
      await send(const LockBuzzerEvent());
      expect(engine.state.game.round.activePlayerId, 'a');
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.game.round.buzzerOpenForAll, isTrue);
      expect(engine.state.game.round.resolvedAttempts, 2);
      await send(const EndRoundEvent());
      await send(const CloseRoundEvent());
      expect(engine.state.game.round.buzzerOpenForAll, isFalse);
    },
  );

  test('manual standard question can retry with zero points and waits after success', () async {
    await engine.close();
    engine = QuizEngineBloc(
      questionBank: const [
        BuzzerQuestion(
          id: 'q',
          prompt: 'Question',
          hostEndsRound: true,
          retryLimit: 0,
          lockOutOnMiss: false,
          scoringRule: FixedPointsRule(correctPoints: 0),
        ),
      ],
      buzzerGraceWindow: const Duration(days: 1),
      now: () => 1000000,
    );
    await send(const PlayerJoinedEvent(Player(id: 'a', name: 'A')));
    await send(const StartRoundEvent('q'));
    await buzz('a');
    await send(const LockBuzzerEvent());
    await send(const JudgeBuzzerEvent(wasCorrect: false));
    expect(engine.state.roundStatus, RoundStatus.locked);
    await send(const ReopenBuzzerEvent());
    await buzz('a');
    await send(const LockBuzzerEvent());
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    expect(engine.state.game.round.buzzerAnswerCorrect, isTrue);
    await send(const ReopenBuzzerEvent());
    expect(engine.state.roundStatus, RoundStatus.locked);
    await send(const EndRoundEvent());
    expect(engine.state.roundStatus, RoundStatus.revealed);
  });

  test(
    'poker waits for host between teams and preserves single settlement',
    () async {
      await engine.close();
      engine = QuizEngineBloc(
        questionBank: const [
          BuzzerQuestion(id: 'q', prompt: 'Question', hostEndsRound: true),
        ],
        teams: const {
          'a': Team(id: 'a', name: 'A'),
          'b': Team(id: 'b', name: 'B'),
        },
        pokerStartingChips: 100,
        buzzerGraceWindow: const Duration(days: 1),
        now: () => 1000000,
      );
      await join();
      await send(const StartRoundEvent('q'));
      for (final id in ['a', 'b']) {
        await send(
          PlacePokerWagerEvent(playerId: id, questionId: 'q', wager: 10),
        );
      }
      await send(const OpenPokerAnswersEvent());
      await buzz('a');
      await buzz('b');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.roundStatus, RoundStatus.locked);
      expect(engine.state.game.round.activePlayerId, isNull);
      await send(const ReopenBuzzerEvent());
      await buzz('a');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await buzz('b');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(engine.state.game.poker!.chips, {'a': 90, 'b': 110});
      expect(engine.state.roundStatus, RoundStatus.locked);
      await send(const EndRoundEvent());
      expect(engine.state.roundStatus, RoundStatus.revealed);
      expect(engine.state.game.poker!.chips, {'a': 90, 'b': 110});
    },
  );

  test(
    'first valid buzz pauses media immediately without changing fair order',
    () async {
      await join();
      await send(const SelectJeopardyCellEvent('q'));
      await buzz('unknown');
      expect(engine.state.game.tvMediaPaused, isFalse);
      await buzz('a');
      expect(engine.state.game.tvMediaPaused, isTrue);
      expect(engine.state.game.redactedForPlayers().tvMediaPaused, isTrue);
      expect(engine.state.roundStatus, RoundStatus.acceptingAnswers);
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      await send(const ReopenBuzzerEvent());
      expect(engine.state.game.tvMediaPaused, isTrue);
      await send(const ControlTvMediaEvent(TvMediaAction.play));
      expect(engine.state.game.tvMediaPaused, isFalse);
      await buzz('b');
      expect(engine.state.game.tvMediaPaused, isTrue);
    },
  );
}
