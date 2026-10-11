/// Unit tests for the Jeopardy format of the quiz engine.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const int kEpoch = 1700000000000000;

const MultipleChoiceQuestion mcLow = MultipleChoiceQuestion(
  id: 'q-mc-low',
  prompt: 'Pick b',
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  correctOptionId: 'b',
);

const BuzzerQuestion buzzHigh = BuzzerQuestion(
  id: 'q-buzz-high',
  prompt: 'Buzz',
  expectedAnswer: 'Gold',
);

const MultipleChoiceQuestion mcDaily = MultipleChoiceQuestion(
  id: 'q-mc-daily',
  prompt: 'Daily pick b',
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  correctOptionId: 'b',
);

const Map<String, Team> teams = {
  'red': Team(id: 'red', name: 'Red'),
  'blue': Team(id: 'blue', name: 'Blue'),
};

JeopardyBoard board({
  bool penalize = false,
  bool allowSteal = true,
  bool dailyDouble = true,
}) => JeopardyBoard(
  rowPoints: const [100, 200],
  penalizeWrongAnswers: penalize,
  allowSteal: allowSteal,
  categories: [
    const JeopardyCategory(
      name: 'Science',
      cells: [
        JeopardyCell(questionId: 'q-mc-low'),
        JeopardyCell(questionId: 'q-buzz-high'),
      ],
    ),
    JeopardyCategory(
      name: 'History',
      cells: [
        JeopardyCell(questionId: 'q-mc-daily', isDailyDouble: dailyDouble),
        JeopardyCell.empty,
      ],
    ),
  ],
);

void main() {
  late QuizEngineBloc engine;

  QuizEngineBloc build(JeopardyBoard jeopardyBoard) => QuizEngineBloc(
    questionBank: const [mcLow, buzzHigh, mcDaily],
    teams: teams,
    mode: const TeamMode(),
    jeopardyBoard: jeopardyBoard,
    now: () => kEpoch,
  );

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> join() async {
    await send(const StartGameEvent());
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada', teamId: 'red')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Linus', teamId: 'blue')),
    );
  }

  Future<void> choose(String playerId, String questionId, String option) =>
      send(
        SubmitAnswerEvent(
          MultipleChoiceAnswer(
            playerId: playerId,
            questionId: questionId,
            clientTimestampMicros: kEpoch,
            clockOffsetMicros: 0,
            optionId: option,
          ),
        ),
      );

  Future<void> buzz(String playerId) async {
    await send(
      BuzzerPressEvent(
        BuzzerPress(
          playerId: playerId,
          questionId: 'q-buzz-high',
          clientTimestampMicros: kEpoch,
          clockOffsetMicros: 0,
        ),
      ),
    );
    await send(const LockBuzzerEvent());
  }

  GameState game() => engine.state.game;

  tearDown(() async => engine.close());

  group('board session', () {
    setUp(() {
      engine = build(board());
    });

    test(
      'only the picking team can select and wager; pending picks stay fixed',
      () async {
        await join();
        await send(const SelectJeopardyCellEvent('q-mc-daily', playerId: 'p2'));
        expect(game().jeopardy!.pendingDailyDoubleId, isNull);
        await send(const SelectJeopardyCellEvent('q-mc-daily', playerId: 'p1'));
        await send(const SelectJeopardyCellEvent('q-mc-low', playerId: 'p1'));
        await send(const SetJeopardyTurnEvent('blue'));
        expect(game().jeopardy!.pendingPickQuestionId, 'q-mc-daily');
        expect(game().jeopardy!.pendingDailyDoubleId, isNull);
        await send(
          const ConfirmQuestionPickEvent(
            questionId: 'q-mc-daily',
            playerId: 'p1',
            accepted: true,
          ),
        );
        expect(game().jeopardy!.pendingDailyDoubleId, 'q-mc-daily');
        expect(game().jeopardy!.currentTeamId, 'red');
        await send(
          const PlaceDailyDoubleWagerEvent(
            100,
            playerId: 'p2',
            questionId: 'q-mc-daily',
          ),
        );
        await send(
          const PlaceDailyDoubleWagerEvent(
            100,
            playerId: 'p1',
            questionId: 'stale',
          ),
        );
        await send(
          const PlaceDailyDoubleWagerEvent(
            201,
            playerId: 'p1',
            questionId: 'q-mc-daily',
          ),
        );
        expect(game().round.question, isNull);
        await send(
          const PlaceDailyDoubleWagerEvent(
            100,
            playerId: 'p1',
            questionId: 'q-mc-daily',
          ),
        );
        expect(game().round.question!.id, 'q-mc-daily');
        expect(game().jeopardy!.activePoints, 100);
        await send(
          const PlaceDailyDoubleWagerEvent(
            200,
            playerId: 'p1',
            questionId: 'q-mc-daily',
          ),
        );
        expect(game().jeopardy!.activePoints, 100);
      },
    );

    test(
      'configured rotation rejects invalid orders and survives the wire',
      () async {
        await join();
        await send(
          const PlayerJoinedEvent(
            Player(id: 'p3', name: 'Grace', teamId: 'green'),
            createdTeam: Team(id: 'green', name: 'Green'),
          ),
        );
        await send(const SetJeopardyOrderEvent(['blue', 'red', 'green']));
        await send(const SetJeopardyOrderEvent(['red', 'red']));
        expect(GameState.fromJson(game().toJson()).jeopardy!.turnOrder, [
          'blue',
          'red',
          'green',
        ]);
        await send(const SelectJeopardyCellEvent('q-mc-low'));
        await choose('p2', 'q-mc-low', 'b');
        expect(game().jeopardy!.currentTeamId, 'red');
        await send(const ResetGameEvent());
        expect(game().jeopardy!.turnOrder, ['blue', 'red', 'green']);
        expect(game().jeopardy!.currentTeamId, 'blue');
      },
    );

    test(
      'TV playback controls are broadcast and reset for the next question',
      () async {
        await join();
        await send(const SelectJeopardyCellEvent('q-mc-low'));
        await send(const ControlTvMediaEvent(TvMediaAction.pause));
        expect(
          GameState.fromJson(game().redactedForPlayers().toJson())
              .tvMediaPaused,
          isTrue,
        );
        await send(const ControlTvMediaEvent(TvMediaAction.restart));
        expect(game().tvMediaPaused, isFalse);
        expect(game().tvMediaRevision, 1);
        await send(const ControlTvMediaEvent(TvMediaAction.pause));
        await choose('p1', 'q-mc-low', 'b');
        expect(game().tvMediaPaused, isFalse);
        await send(const ControlTvMediaEvent(TvMediaAction.pause));
        await send(const SelectJeopardyCellEvent('q-buzz-high'));
        expect(game().tvMediaPaused, isFalse);
      },
    );

    test('starts with the first team picking', () {
      expect(game().jeopardy?.currentTeamId, 'red');
    });

    test('players never learn where the Daily Doubles are', () {
      final redacted = game().redactedForPlayers();

      expect(redacted.jeopardy?.board.isDailyDouble('q-mc-daily'), isFalse);
      expect(game().jeopardy?.board.isDailyDouble('q-mc-daily'), isTrue);
    });

    test('survives a JSON round trip', () {
      final restored = GameState.fromJson(game().toJson());

      expect(restored.jeopardy, game().jeopardy);
    });

    test('selecting a cell stages its question for the row points', () async {
      await send(const SelectJeopardyCellEvent('q-buzz-high'));

      expect(game().round.question?.id, 'q-buzz-high');
      expect(game().round.status, RoundStatus.acceptingAnswers);
      expect(game().jeopardy?.activePoints, 200);
    });

    test('a plain start event is routed through the board', () async {
      await send(const StartRoundEvent('q-buzz-high'));

      expect(game().jeopardy?.activePoints, 200);
    });

    test('refuses a second pick while a question is on stage', () async {
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await send(const SelectJeopardyCellEvent('q-buzz-high'));

      expect(game().round.question?.id, 'q-mc-low');
      expect(engine.state.notice, contains('Finish'));
    });

    test(
      'the picking team scores the row points and the pick moves on',
      () async {
        await join();
        await send(const SelectJeopardyCellEvent('q-mc-low'));
        await choose('p1', 'q-mc-low', 'b');

        expect(game().round.status, RoundStatus.revealed);
        expect(game().scores.scoreOf('p1'), 100);
        expect(game().jeopardy?.currentTeamId, 'blue');
        expect(game().completedQuestionIds, contains('q-mc-low'));
      },
    );

    test('a question cannot be played twice', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'b');
      await send(const SelectJeopardyCellEvent('q-mc-low'));

      expect(engine.state.notice, contains('already played'));
    });

    test('the other team may not answer before the picking team', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p2', 'q-mc-low', 'b');

      expect(game().round.answers, isEmpty);
      expect(engine.state.notice, contains('picking team'));
    });

    test('only one answer per team counts', () async {
      await send(
        const PlayerJoinedEvent(Player(id: 'p3', name: 'Grace', teamId: 'red')),
      );
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'a');
      await choose('p3', 'q-mc-low', 'b');

      expect(game().round.answers.keys, isNot(contains('p3')));
    });

    test('a miss opens the question to the other teams', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'a');

      expect(game().round.status, RoundStatus.acceptingAnswers);
      expect(game().jeopardy?.isStealRound, isTrue);

      // Now the picking team is shut out and the others may answer.
      await choose('p1', 'q-mc-low', 'b');
      expect(game().round.answers, isEmpty);

      await choose('p2', 'q-mc-low', 'b');
      expect(game().round.status, RoundStatus.revealed);
      expect(game().scores.scoreOf('p2'), 100);
      expect(game().scores.scoreOf('p1'), 0);
      // The pick still rotates by one: red picked, so blue picks next.
      expect(game().jeopardy?.currentTeamId, 'blue');
    });

    test('closing the round returns to the board', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'b');
      await send(const CloseRoundEvent());

      expect(game().round.question, isNull);
      expect(game().jeopardy?.activePoints, isNull);
    });

    test('the host can override whose turn it is', () async {
      await send(const SetJeopardyTurnEvent('blue'));

      expect(game().jeopardy?.currentTeamId, 'blue');
    });

    test('a reset restores the board and the first picker', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'b');
      await send(const ResetGameEvent());

      expect(game().completedQuestionIds, isEmpty);
      expect(game().jeopardy?.currentTeamId, 'red');
      expect(game().scores.scoreOf('p1'), 0);
    });
  });

  group('buzzer on the board', () {
    setUp(() {
      engine = build(board(penalize: true));
    });

    test('a miss costs the row points and the other team steals', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-buzz-high'));
      await buzz('p1');
      await send(const JudgeBuzzerEvent(wasCorrect: false));

      expect(game().scores.scoreOf('p1'), -200);
      expect(game().jeopardy?.isStealRound, isTrue);
      expect(game().round.status, RoundStatus.acceptingAnswers);

      await buzz('p2');
      await send(const JudgeBuzzerEvent(wasCorrect: true));

      expect(game().scores.scoreOf('p2'), 200);
      expect(game().round.status, RoundStatus.revealed);
    });
  });

  group('without stealing', () {
    setUp(() {
      engine = build(board(allowSteal: false));
    });

    test('a miss ends the question', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-low'));
      await choose('p1', 'q-mc-low', 'a');

      expect(game().round.status, RoundStatus.revealed);
      expect(game().jeopardy?.isStealRound, isFalse);
      // No penalty configured.
      expect(game().scores.scoreOf('p1'), 0);
    });
  });

  group('Daily Double', () {
    setUp(() {
      engine = build(board());
    });

    test('waits for a wager before the question opens', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-daily'));

      expect(game().round.question, isNull);
      expect(game().jeopardy?.pendingDailyDoubleId, 'q-mc-daily');
    });

    test('rejects a wager above the allowed maximum', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-daily'));
      await send(const PlaceDailyDoubleWagerEvent(5000));

      expect(game().round.question, isNull);
      expect(engine.state.notice, contains('between 1 and 200'));
    });

    test('scores the wager for a correct answer', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-daily'));
      await send(const PlaceDailyDoubleWagerEvent(150));
      expect(game().jeopardy?.activeIsDailyDouble, isTrue);

      await choose('p1', 'q-mc-daily', 'b');

      expect(game().scores.scoreOf('p1'), 150);
      expect(game().jeopardy?.pendingDailyDoubleId, isNull);
    });

    test('loses the wager for a wrong answer and cannot be stolen', () async {
      await join();
      await send(const SelectJeopardyCellEvent('q-mc-daily'));
      await send(const PlaceDailyDoubleWagerEvent(150));
      await choose('p1', 'q-mc-daily', 'a');

      expect(game().scores.scoreOf('p1'), -150);
      expect(game().round.status, RoundStatus.revealed);
      expect(game().jeopardy?.isStealRound, isFalse);
    });
  });
}
