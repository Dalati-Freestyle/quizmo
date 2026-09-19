/// Unit tests for the quiz state machine.
///
/// The centrepiece is `declares the fastest press even when it arrives last`:
/// it encodes architecture Rule 3 as an executable specification.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

/// Host clock at which every scenario starts.
const int kEpoch = 1700000000000000;

const MultipleChoiceQuestion choiceQuestion = MultipleChoiceQuestion(
  id: 'q-mc',
  prompt: 'Pick the right one',
  options: [
    AnswerOption(id: 'a', label: 'Wrong'),
    AnswerOption(id: 'b', label: 'Right'),
  ],
  correctOptionId: 'b',
  scoringRule: SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10),
  timeLimit: Duration(seconds: 20),
);

const BuzzerQuestion buzzerQuestion = BuzzerQuestion(
  id: 'q-buzz',
  prompt: 'Buzz to answer',
  expectedAnswer: 'Gold',
  scoringRule: FirstBuzzerRule(points: 15, penalty: -5, rankDecay: 5),
  timeLimit: Duration(seconds: 20),
);

const Map<String, Team> teams = {
  'red': Team(id: 'red', name: 'Red'),
  'blue': Team(id: 'blue', name: 'Blue'),
};

void main() {
  late int nowMicros;
  late QuizEngineBloc engine;

  QuizEngineBloc buildEngine({
    GameMode mode = const SoloMode(),
    Duration grace = const Duration(milliseconds: 20),
  }) => QuizEngineBloc(
    questionBank: const [choiceQuestion, buzzerQuestion],
    teams: teams,
    mode: mode,
    buzzerGraceWindow: grace,
    now: () => nowMicros,
  );

  Future<void> join(String id, String name, {String? teamId}) async {
    engine.add(
      PlayerJoinedEvent(Player(id: id, name: name, teamId: teamId)),
    );
    await pumpEventQueue();
  }

  setUp(() {
    nowMicros = kEpoch;
    engine = buildEngine();
  });

  tearDown(() async => engine.close());

  group('lobby', () {
    test('registers players and seeds their score', () async {
      await join('p1', 'Ada');

      expect(engine.state.game.players['p1']?.name, 'Ada');
      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.game.connectedPlayers, hasLength(1));
    });

    test('a rejoin flips the player back to connected', () async {
      await join('p1', 'Ada');
      engine.add(const PlayerLeftEvent('p1'));
      await pumpEventQueue();
      expect(engine.state.game.players['p1']?.isConnected, isFalse);

      await join('p1', 'Ada');
      expect(engine.state.game.players['p1']?.isConnected, isTrue);
      expect(engine.state.game.players, hasLength(1));
    });

    test('records the clock quality reported by a client', () async {
      await join('p1', 'Ada');
      engine.add(
        const TimeSyncEvent(
          playerId: 'p1',
          clockOffsetMicros: 4200,
          roundTripMicros: 18000,
        ),
      );
      await pumpEventQueue();

      expect(engine.state.game.players['p1']?.clockOffsetMicros, 4200);
      expect(engine.state.game.players['p1']?.latency.inMilliseconds, 9);
    });
  });

  group('multiple choice round', () {
    test('scores by latency adjusted submission time', () async {
      await join('p1', 'Ada');
      await join('p2', 'Linus');

      engine.add(const StartRoundEvent('q-mc'));
      await pumpEventQueue();

      // Ada answers 2 s into the round, Linus 18 s in — both correct.
      engine.add(
        SubmitAnswerEvent(
          MultipleChoiceAnswer(
            playerId: 'p1',
            questionId: 'q-mc',
            clientTimestampMicros: kEpoch + 2000000,
            clockOffsetMicros: 0,
            optionId: 'b',
          ),
        ),
      );
      engine.add(
        SubmitAnswerEvent(
          MultipleChoiceAnswer(
            playerId: 'p2',
            questionId: 'q-mc',
            clientTimestampMicros: kEpoch + 18000000,
            clockOffsetMicros: 0,
            optionId: 'b',
          ),
        ),
      );
      await pumpEventQueue();

      // Both answered, so the engine reveals on its own.
      expect(engine.state.game.round.status, RoundStatus.revealed);
      expect(engine.state.game.scores.scoreOf('p1'), 19);
      expect(engine.state.game.scores.scoreOf('p2'), 11);
      expect(engine.state.game.completedQuestionIds, contains('q-mc'));
    });

    test('keeps only the first answer of a player', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-mc'));
      await pumpEventQueue();

      for (final optionId in ['a', 'b']) {
        engine.add(
          SubmitAnswerEvent(
            MultipleChoiceAnswer(
              playerId: 'p1',
              questionId: 'q-mc',
              clientTimestampMicros: kEpoch,
              clockOffsetMicros: 0,
              optionId: optionId,
            ),
          ),
        );
      }
      await pumpEventQueue();

      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.game.round.status, RoundStatus.revealed);
    });

    test('ignores a submission that targets a stale round', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-mc'));
      await pumpEventQueue();

      engine.add(
        SubmitAnswerEvent(
          const MultipleChoiceAnswer(
            playerId: 'p1',
            questionId: 'q-other',
            clientTimestampMicros: kEpoch,
            clockOffsetMicros: 0,
            optionId: 'b',
          ),
        ),
      );
      await pumpEventQueue();

      expect(engine.state.game.round.answers, isEmpty);
      expect(engine.state.notice, contains('stale'));
    });
  });

  group('buzzer round', () {
    /// Builds a press whose *host* timestamp is `offsetFromStart` after the
    /// round began, while the client clock is skewed by [clockOffsetMicros].
    BuzzerPress pressAt(
      String playerId, {
      required int offsetFromStartMicros,
      required int clockOffsetMicros,
    }) => BuzzerPress(
      playerId: playerId,
      questionId: 'q-buzz',
      clientTimestampMicros:
          kEpoch + offsetFromStartMicros + clockOffsetMicros,
      clockOffsetMicros: clockOffsetMicros,
    );

    test('declares the fastest press even when it arrives last', () async {
      await join('p1', 'Ada');
      await join('p2', 'Linus');

      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      // Linus' packet reaches the host first, but Ada physically pressed
      // 80 ms earlier. Their clocks are skewed in opposite directions, so
      // only the offset corrected timestamps reveal the true order.
      final linus = pressAt(
        'p2',
        offsetFromStartMicros: 200000,
        clockOffsetMicros: -300000,
      );
      final ada = pressAt(
        'p1',
        offsetFromStartMicros: 120000,
        clockOffsetMicros: 500000,
      );

      engine.add(BuzzerPressEvent(linus));
      engine.add(BuzzerPressEvent(ada));
      await pumpEventQueue();

      expect(
        engine.state.game.round.buzzerQueue.map((press) => press.playerId),
        ['p1', 'p2'],
        reason: 'the queue must be ordered by host timestamp, not arrival',
      );

      // Naive ordering would have crowned Linus.
      expect(ada.hostTimestampMicros, lessThan(linus.hostTimestampMicros));

      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();

      expect(engine.state.game.round.status, RoundStatus.locked);
      expect(engine.state.game.round.activePlayerId, 'p1');
      expect(
        engine.state.game.round.gapToFastest(linus).inMilliseconds,
        80,
      );
    });

    test('locks automatically once the grace window elapsed', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      await pumpEventQueue();
      expect(engine.state.game.round.status, RoundStatus.acceptingAnswers);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue();

      expect(engine.state.game.round.status, RoundStatus.locked);
      expect(engine.state.game.round.activePlayerId, 'p1');
    });

    test('rewards a correct answer and reveals the round', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();

      engine.add(const JudgeBuzzerEvent(wasCorrect: true));
      await pumpEventQueue();

      expect(engine.state.game.scores.scoreOf('p1'), 15);
      expect(engine.state.game.round.status, RoundStatus.revealed);
    });

    test('hands the floor to the runner up after a missed steal', () async {
      await join('p1', 'Ada');
      await join('p2', 'Linus');

      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      engine.add(
        BuzzerPressEvent(
          pressAt('p2', offsetFromStartMicros: 9000, clockOffsetMicros: 0),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();
      expect(engine.state.game.round.activePlayerId, 'p1');

      engine.add(const JudgeBuzzerEvent(wasCorrect: false));
      await pumpEventQueue();

      expect(engine.state.game.scores.scoreOf('p1'), -5);
      expect(engine.state.game.round.activePlayerId, 'p2');
      expect(engine.state.game.round.lockedOutPlayerIds, contains('p1'));

      // The steal is worth less than the original press.
      engine.add(const JudgeBuzzerEvent(wasCorrect: true));
      await pumpEventQueue();
      expect(engine.state.game.scores.scoreOf('p2'), 10);
    });

    test('reopens the buzzer when nobody is left in the queue', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();

      engine.add(const JudgeBuzzerEvent(wasCorrect: false));
      await pumpEventQueue();

      expect(engine.state.game.round.status, RoundStatus.acceptingAnswers);
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      expect(engine.state.game.round.activePlayerId, isNull);
    });

    test('a shared team buzzer locks out the team mates', () async {
      await engine.close();
      engine = buildEngine(mode: const TeamMode());

      await join('p1', 'Ada', teamId: 'red');
      await join('p2', 'Grace', teamId: 'red');
      await join('p3', 'Linus', teamId: 'blue');

      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();

      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();

      expect(engine.state.game.round.lockedOutPlayerIds, contains('p2'));
      expect(
        engine.state.game.round.lockedOutPlayerIds,
        isNot(contains('p3')),
      );
    });

    test('aggregates points per team', () async {
      await engine.close();
      engine = buildEngine(mode: const TeamMode());

      await join('p1', 'Ada', teamId: 'red');
      await join('p2', 'Grace', teamId: 'red');

      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();
      engine.add(
        BuzzerPressEvent(
          pressAt('p1', offsetFromStartMicros: 1000, clockOffsetMicros: 0),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();
      engine.add(const JudgeBuzzerEvent(wasCorrect: true));
      await pumpEventQueue();

      expect(engine.state.game.teamScores['red'], 15);
    });
  });

  group('session control', () {
    test('NextQuestionEvent walks the bank in order', () async {
      await join('p1', 'Ada');

      engine.add(const NextQuestionEvent());
      await pumpEventQueue();
      expect(engine.state.game.round.question?.id, 'q-mc');

      engine.add(const RevealRoundEvent());
      await pumpEventQueue();
      engine.add(const NextQuestionEvent());
      await pumpEventQueue();
      expect(engine.state.game.round.question?.id, 'q-buzz');
    });

    test('ResetGameEvent clears the scores but keeps the roster', () async {
      await join('p1', 'Ada');
      engine.add(const StartRoundEvent('q-buzz'));
      await pumpEventQueue();
      engine.add(
        BuzzerPressEvent(
          const BuzzerPress(
            playerId: 'p1',
            questionId: 'q-buzz',
            clientTimestampMicros: kEpoch,
            clockOffsetMicros: 0,
          ),
        ),
      );
      engine.add(const LockBuzzerEvent());
      await pumpEventQueue();
      engine.add(const JudgeBuzzerEvent(wasCorrect: true));
      await pumpEventQueue();
      expect(engine.state.game.scores.scoreOf('p1'), 15);

      engine.add(const ResetGameEvent());
      await pumpEventQueue();

      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.game.players, hasLength(1));
      expect(engine.state.game.questionBank, hasLength(2));
      expect(engine.state.game.round.status, RoundStatus.idle);
    });
  });
}

