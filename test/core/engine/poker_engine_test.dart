import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const question = TrueFalseQuestion(
  id: 'q',
  prompt: 'True?',
  correctAnswer: true,
);
const teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

void main() {
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> wager(String player, int amount, {String id = 'q'}) => send(
    PlacePokerWagerEvent(playerId: player, questionId: id, wager: amount),
  );
  Future<void> answer(String player, bool value) => send(
    SubmitAnswerEvent(
      TrueFalseAnswer(
        playerId: player,
        questionId: 'q',
        clientTimestampMicros: 1000,
        clockOffsetMicros: 0,
        value: value,
      ),
    ),
  );

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: const [question],
      teams: teams,
      mode: const TeamMode(),
      pokerStartingChips: 100,
      now: () => 1000,
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Two', teamId: 'b')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p3', name: 'Mate', teamId: 'a')),
    );
    await send(const StartRoundEvent('q'));
  });
  tearDown(() => engine.close());

  test(
    'correct doubles the stake, wrong loses the stake, once per team',
    () async {
      await wager('p1', 20);
      await wager('p2', 30);
      expect(engine.state.game.teamScores, {'a': 80, 'b': 70});
      await answer('p1', true);
      expect(engine.state.game.round.answers, isEmpty);
      await send(const OpenPokerAnswersEvent());
      await answer('p1', true);
      await answer('p3', true);
      expect(engine.state.game.round.answers.length, 1);
      await answer('p2', false);
      expect(engine.state.game.teamScores, {'a': 120, 'b': 70});
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 120, 'b': 70});
      expect(engine.state.game.scores.history, isEmpty);
    },
  );

  test(
    'rejects negative, excessive, stale, unknown and repeated wagers',
    () async {
      await wager('p1', -1);
      await wager('p1', 101);
      await wager('p1', 10, id: 'old');
      await wager('unknown', 10);
      expect(engine.state.game.poker!.wagers, isEmpty);
      await wager('p1', 100);
      await wager('p3', 1);
      expect(engine.state.game.teamScores['a'], 0);
      expect(engine.state.game.poker!.wagers['a'], 100);
      await send(const OpenPokerAnswersEvent());
      await wager('p2', 10);
      expect(engine.state.game.poker!.wagers.containsKey('b'), isFalse);
      await answer('p1', true);
      expect(engine.state.game.teamScores['a'], 200);
    },
  );

  test('unanswered wager is lost and reset restores initial chips', () async {
    await wager('p1', 100);
    await send(const OpenPokerAnswersEvent());
    await send(const RevealRoundEvent());
    expect(engine.state.game.teamScores, {'a': 0, 'b': 100});
    await send(const ResetGameEvent());
    expect(engine.state.game.teamScores, {'a': 100, 'b': 100});
    expect(engine.state.game.poker!.wagers, isEmpty);
    expect(engine.state.game.totalQuestionCount, 1);
  });

  test(
    'redacted wire snapshot retains chips but hides answers and solution',
    () async {
      await wager('p1', 20);
      await wager('p2', 10);
      await send(const OpenPokerAnswersEvent());
      await answer('p1', true);
      final snapshot = GameState.fromJson(
        engine.state.game.redactedForPlayers().toJson(),
      );
      expect(snapshot.poker, engine.state.game.poker);
      expect(snapshot.round.answers, isEmpty);
      expect(
        (snapshot.round.question as TrueFalseQuestion).correctAnswer,
        isNull,
      );
      expect(snapshot.questionBank, isEmpty);
      expect(snapshot.totalQuestionCount, 1);
    },
  );

  test('skip and bankrupt teams cannot answer without a stake', () async {
    await wager('p1', 0);
    await send(const OpenPokerAnswersEvent());
    await answer('p1', true);
    expect(engine.state.game.round.answers, isEmpty);
    expect(engine.state.game.teamScores['a'], 100);
  });

  test('payout uses all or nothing', () {
    expect(pokerChipPayout(wager: 20, isCorrect: true), 40);
    expect(pokerChipPayout(wager: 20, isCorrect: false), 0);
  });

  test(
    'partial correctness loses the stake and the next question starts fresh',
    () async {
      await engine.close();
      engine = QuizEngineBloc(
        questionBank: const [
          EstimationQuestion(id: 'q', prompt: 'Estimate', correctValue: 100),
          TrueFalseQuestion(id: 'next', prompt: 'Next', correctAnswer: true),
        ],
        teams: teams,
        pokerStartingChips: 100,
        now: () => 1000,
      );
      await send(
        const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
      );
      await send(const StartRoundEvent('q'));
      await wager('p1', 20);
      await send(const OpenPokerAnswersEvent());
      await send(
        const SubmitAnswerEvent(
          EstimationAnswer(
            playerId: 'p1',
            questionId: 'q',
            clientTimestampMicros: 1000,
            clockOffsetMicros: 0,
            value: 90,
          ),
        ),
      );
      expect(engine.state.game.teamScores['a'], 80);
      expect(engine.state.game.round.status, RoundStatus.revealed);
      await send(const NextQuestionEvent());
      expect(engine.state.game.round.question!.id, 'next');
      expect(engine.state.game.poker!.betting, isTrue);
      expect(engine.state.game.poker!.wagers, isEmpty);
      expect(engine.state.game.poker!.settledTeamIds, isEmpty);
      expect(engine.state.game.teamScores['a'], 80);
    },
  );

  test(
    'buzzer settles all teams once while keeping latency ordering',
    () async {
      await engine.close();
      engine = QuizEngineBloc(
        questionBank: const [BuzzerQuestion(id: 'q', prompt: 'Buzz')],
        teams: teams,
        pokerStartingChips: 100,
        now: () => 1000,
        buzzerGraceWindow: const Duration(days: 1),
      );
      await send(
        const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
      );
      await send(
        const PlayerJoinedEvent(Player(id: 'p2', name: 'Two', teamId: 'b')),
      );
      await send(
        const PlayerJoinedEvent(Player(id: 'p3', name: 'Mate', teamId: 'a')),
      );
      await send(const StartRoundEvent('q'));
      await wager('p1', 20);
      await wager('p2', 30);
      await send(const OpenPokerAnswersEvent());
      await send(
        const BuzzerPressEvent(
          BuzzerPress(
            playerId: 'p1',
            questionId: 'q',
            clientTimestampMicros: 1100,
            clockOffsetMicros: 0,
          ),
        ),
      );
      await send(
        const BuzzerPressEvent(
          BuzzerPress(
            playerId: 'p2',
            questionId: 'q',
            clientTimestampMicros: 1200,
            clockOffsetMicros: 200,
          ),
        ),
      );
      await send(const LockBuzzerEvent());
      expect(engine.state.game.round.activePlayerId, 'p2');
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(engine.state.game.teamScores['b'], 130);
      expect(engine.state.game.round.activePlayerId, 'p1');
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.game.round.status, RoundStatus.revealed);
      expect(engine.state.game.teamScores, {'a': 80, 'b': 130});
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(engine.state.game.teamScores, {'a': 80, 'b': 130});
    },
  );

  test(
    'a pending stake cannot be discarded by starting another question',
    () async {
      await wager('p1', 20);
      await send(const StartRoundEvent('q'));
      expect(engine.state.game.poker!.wagers, {'a': 20});
      await send(const ChangeGameModeEvent(SoloMode()));
      expect(engine.state.game.mode, const TeamMode());
      await send(
        const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'b')),
      );
      expect(engine.state.game.players['p1']!.teamId, 'a');
    },
  );
}
