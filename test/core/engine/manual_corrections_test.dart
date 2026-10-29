import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const _epoch = 1700000000000000;
const _question = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Question',
  acceptedAnswers: ['secret solution'],
  manualGrading: true,
  scoringRule: FirstBuzzerRule(points: 20, penalty: -5, rankDecay: 5),
);
const _buzzer = BuzzerQuestion(
  id: 'q',
  prompt: 'Buzz',
  expectedAnswer: 'secret solution',
);
const _teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

void main() {
  late QuizEngineBloc engine;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start({
    bool poker = false,
    bool buzzer = false,
    bool jeopardy = false,
  }) async {
    engine = QuizEngineBloc(
      questionBank: [buzzer ? _buzzer : _question],
      teams: _teams,
      mode: jeopardy ? const TeamMode() : const SoloMode(),
      pokerStartingChips: poker ? 100 : null,
      autoContinueBuzzer: false,
      jeopardyBoard: jeopardy
          ? const JeopardyBoard(
              rowPoints: [100],
              penalizeWrongAnswers: true,
              categories: [
                JeopardyCategory(
                  name: 'Test',
                  cells: [JeopardyCell(questionId: 'q')],
                ),
              ],
            )
          : null,
      now: () => _epoch,
    );
    addTearDown(engine.close);
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Two', teamId: 'b')),
    );
    await send(const StartRoundEvent('q'));
    if (poker) {
      await send(
        const PlacePokerWagerEvent(playerId: 'p1', questionId: 'q', wager: 20),
      );
      await send(
        const PlacePokerWagerEvent(playerId: 'p2', questionId: 'q', wager: 20),
      );
      await send(const OpenPokerAnswersEvent());
    }
  }

  CorrectScoreEvent correction(
    String id,
    int delta, {
    String playerId = 'p1',
  }) => CorrectScoreEvent(
    requestId: id,
    playerId: playerId,
    questionId: 'q',
    roundStartedAt: engine.state.game.round.startedAtHostMicros!,
    delta: delta,
    reason: 'Reason $id',
  );

  Future<void> answer(String id, int elapsed) => send(
    SubmitAnswerEvent(
      ShortAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: _epoch + elapsed,
        clockOffsetMicros: 0,
        text: 'secret solution',
      ),
    ),
  );

  JudgeAnswerEvent grade(String id, bool correct) => JudgeAnswerEvent(
    playerId: id,
    questionId: 'q',
    startedAtHostMicros: engine.state.game.round.startedAtHostMicros!,
    wasCorrect: correct,
  );

  Future<void> buzz() async {
    await send(
      const BuzzerPressEvent(
        BuzzerPress(
          playerId: 'p1',
          questionId: 'q',
          clientTimestampMicros: _epoch + 1,
          clockOffsetMicros: 0,
        ),
      ),
    );
    await send(const LockBuzzerEvent());
  }

  test(
    'counter-bookings preserve later scores, rankings, and immutable history',
    () async {
      await start();
      await send(correction('one', 20));
      final first = engine.state.game.corrections.single;
      await send(correction('two', 10));
      await send(correction('three', 15, playerId: 'p2'));
      expect(engine.state.game.scores.ranking.first.key, 'p1');
      await send(UndoCorrectionEvent(first.id, reason: 'Wrong player'));
      expect(engine.state.game.scores.byPlayer, {'p1': 10, 'p2': 15});
      expect(engine.state.game.scores.ranking.first.key, 'p2');
      final history = engine.state.game.corrections;
      expect(history.first, first);
      expect(history.last.reversesId, first.id);
      expect(history.last.beforeValue, 30);
      expect(history.last.afterValue, 10);
      expect(history.last.reason, 'Wrong player');
      expect(engine.state.game.scores.history.map((e) => e.points), [
        20,
        10,
        15,
        -20,
      ]);
      await send(UndoCorrectionEvent(first.id));
      await send(UndoCorrectionEvent(history.last.id));
      await send(const UndoCorrectionEvent('unknown'));
      expect(engine.state.game.corrections, history);
      expect(engine.state.game.scores.scoreOf('p1'), 10);
    },
  );

  test(
    'duplicate correction requests and invalid actions do not book twice',
    () async {
      await start();
      final event = correction('one', 20);
      await send(event);
      await send(event);
      expect(engine.state.notice, isNotNull);
      await send(correction('zero', 0));
      await send(correction('unknown', 5, playerId: 'missing'));
      await send(
        CorrectScoreEvent(
          requestId: 'stale',
          playerId: 'p1',
          questionId: 'q',
          roundStartedAt: _epoch - 1,
          delta: 100,
        ),
      );
      expect(engine.state.game.corrections, hasLength(1));
      expect(engine.state.game.scores.scoreOf('p1'), 20);
    },
  );

  test('grading undo is scoped to one answer and settlement uses only final verdicts', () async {
    await start();
    await answer('p1', 1);
    await answer('p2', 2);
    await send(grade('p1', true));
    final first = engine.state.game.corrections.single;
    await send(grade('p1', true));
    expect(engine.state.game.corrections, hasLength(1));
    await send(grade('p1', false));
    final second = engine.state.game.corrections.last;
    await send(grade('p2', true));
    await send(UndoCorrectionEvent(first.id));
    expect(engine.state.notice, isNotNull);
    expect(engine.state.game.round.answerVerdicts['p1'], 0);
    await send(UndoCorrectionEvent(second.id));
    expect(engine.state.game.round.answerVerdicts, {'p1': 1, 'p2': 1});
    await send(UndoCorrectionEvent(first.id));
    expect(engine.state.game.round.answerVerdicts, {'p2': 1});
    await send(grade('p1', false));
    await send(const RevealRoundEvent());
    expect(engine.state.game.scores.byPlayer, {'p1': -5, 'p2': 20});
    final count = engine.state.game.corrections.length;
    await send(UndoCorrectionEvent(engine.state.game.corrections.last.id));
    expect(engine.state.notice, contains('aufgelöst'));
    expect(engine.state.game.corrections, hasLength(count));
    await send(const RevealRoundEvent());
    expect(engine.state.game.scores.byPlayer, {'p1': -5, 'p2': 20});
  });

  test('buzzer undo restores floor and inverse points without discarding later adjustments', () async {
    await start(buzzer: true);
    await buzz();
    final before = engine.state.game.round;
    await send(const JudgeBuzzerEvent(wasCorrect: false));
    final decision = engine.state.game.corrections.single;
    await send(correction('extra', 7));
    await send(UndoCorrectionEvent(decision.id));
    expect(engine.state.game.round, before);
    expect(engine.state.game.scores.scoreOf('p1'), 7);
    expect(engine.state.game.corrections.last.reversesId, decision.id);
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    expect(engine.state.game.corrections.last.kind, CorrectionKind.buzzer);
  });

  test('buzzer undo is blocked after a dependent game action', () async {
    await start(buzzer: true);
    await buzz();
    await send(const JudgeBuzzerEvent(wasCorrect: false));
    final decision = engine.state.game.corrections.single;
    await send(const ReopenBuzzerEvent(forAll: true));
    final before = engine.state.game;
    await send(UndoCorrectionEvent(decision.id));
    expect(engine.state.game, before);
    expect(engine.state.notice, contains('Spielaktionen'));
  });

  test(
    'Jeopardy judgment undo reverses row points and restores board turn',
    () async {
      await start(buzzer: true, jeopardy: true);
      await buzz();
      final before = engine.state.game;
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(engine.state.game.teamScores['a'], 100);
      final entry = engine.state.game.corrections.single;
      await send(UndoCorrectionEvent(entry.id));
      expect(engine.state.game.teamScores['a'], 0);
      expect(engine.state.game.jeopardy, before.jeopardy);
      expect(
        engine.state.game.completedQuestionIds,
        before.completedQuestionIds,
      );
      expect(engine.state.game.isFinished, before.isFinished);
      expect(engine.state.game.round, before.round);
    },
  );

  test(
    'poker grading changes settle exactly once using the final verdict',
    () async {
      await start(poker: true);
      await answer('p1', 1);
      await answer('p2', 2);
      await send(grade('p1', false));
      final wrong = engine.state.game.corrections.single;
      await send(grade('p1', true));
      final right = engine.state.game.corrections.last;
      await send(UndoCorrectionEvent(right.id));
      await send(grade('p2', true));
      await send(const RevealRoundEvent());
      expect(engine.state.game.poker!.chips, {'a': 80, 'b': 120});
      await send(UndoCorrectionEvent(wrong.id));
      expect(engine.state.notice, contains('aufgelöst'));
      expect(engine.state.game.poker!.chips, {'a': 80, 'b': 120});
    },
  );

  test(
    'poker corrections preserve later changes and reject negative balances',
    () async {
      await start(poker: true);
      await send(correction('one', 10));
      final first = engine.state.game.corrections.single;
      await send(correction('two', 5));
      await send(UndoCorrectionEvent(first.id));
      expect(engine.state.game.poker!.chips['a'], 85);
      expect(engine.state.game.scores.scoreOf('p1'), 0);
      await send(correction('too-much', -1000));
      expect(engine.state.notice, contains('negative Chips'));
      expect(engine.state.game.corrections, hasLength(3));
      await send(correction('spent', -85));
      final before = engine.state.game;
      await send(UndoCorrectionEvent(engine.state.game.corrections[1].id));
      expect(engine.state.notice, contains('bereits eingesetzt'));
      expect(engine.state.game, before);
    },
  );

  test('poker buzzer undo restores settlement and can settle again', () async {
    await start(buzzer: true, poker: true);
    await buzz();
    final before = engine.state.game;
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    expect(engine.state.game.poker!.chips['a'], 120);
    await send(UndoCorrectionEvent(engine.state.game.corrections.single.id));
    expect(engine.state.game.round, before.round);
    expect(engine.state.game.poker, before.poker);
    await send(const JudgeBuzzerEvent(wasCorrect: false));
    expect(engine.state.game.poker!.chips['a'], 80);
    expect(engine.state.game.poker!.settledTeamIds, contains('a'));
  });

  test(
    'host audit including reasons and round solutions never reaches guests',
    () async {
      await start(buzzer: true);
      await buzz();
      await send(
        const JudgeBuzzerEvent(wasCorrect: true, reason: 'private host reason'),
      );
      for (final deferred in [false, true]) {
        final game = engine.state.game.copyWith(
          revealMode: deferred
              ? SolutionRevealMode.atEnd
              : SolutionRevealMode.afterEachQuestion,
          isFinished: false,
        );
        final redacted = game.redactedForPlayers();
        expect(redacted.corrections, isEmpty);
        expect(
          jsonEncode(redacted.toJson()),
          isNot(contains('private host reason')),
        );
        if (deferred) {
          expect(
            jsonEncode(redacted.toJson()),
            isNot(contains('secret solution')),
          );
          expect(redacted.scores.history, isEmpty);
        }
      }
    },
  );

  test('checkpoint restores history without replaying and keeps request deduplication', () async {
    await start();
    await send(correction('one', 20));
    await send(correction('two', 5));
    await send(UndoCorrectionEvent(engine.state.game.corrections.first.id));
    final quiz = Quiz(
      id: 'quiz',
      name: 'Quiz',
      description: 'Recovery fixture',
      category: 'Tests',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [_question],
      teams: _teams.values.toList(),
    );
    final checkpoint = SessionCheckpoint(
      sessionId: 'session-corrections-1234',
      quiz: quiz,
      game: engine.state.game,
      savedAtMicros: _epoch,
      resumeTokenHashes: {'p1': 'a' * 64, 'p2': 'b' * 64},
    );
    checkpoint.validate();
    final invalidJson = engine.state.game.toJson();
    final invalidEntries = invalidJson.readList(
      'corrections',
      (entry) => entry,
    );
    invalidEntries.first['scoreDeltas'] = <String, int>{};
    invalidJson['corrections'] = invalidEntries;
    expect(
      () => SessionCheckpoint(
        sessionId: checkpoint.sessionId,
        quiz: quiz,
        game: GameState.fromJson(invalidJson),
        savedAtMicros: _epoch,
        resumeTokenHashes: checkpoint.resumeTokenHashes,
      ).validate(),
      throwsA(isA<RecoveryException>()),
    );
    final saved = SessionCheckpoint.decode(
      checkpoint.encode(),
      quizDocument: jsonEncode(quiz.toJson()),
    );
    final restored = QuizEngineBloc(
      restoredGame: saved.pausedGame(),
      now: () => _epoch,
    );
    addTearDown(restored.close);
    expect(restored.state.game.corrections, engine.state.game.corrections);
    expect(restored.state.game.scores.scoreOf('p1'), 5);
    restored.add(const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime));
    await pumpEventQueue();
    restored.add(correction('two', 5));
    await pumpEventQueue();
    expect(restored.state.game.scores.scoreOf('p1'), 5);
    restored.add(UndoCorrectionEvent(restored.state.game.corrections[1].id));
    await pumpEventQueue();
    expect(restored.state.game.scores.scoreOf('p1'), 0);
    expect(restored.state.game.corrections, hasLength(4));
  });

  test('reset clears the audit together with scores', () async {
    await start();
    await send(correction('one', 10));
    await send(const ResetGameEvent());
    expect(engine.state.game.corrections, isEmpty);
    expect(engine.state.game.scores.scoreOf('p1'), 0);
  });

  test(
    'a duplicate request stays consumed after its correction is undone',
    () async {
      await start();
      final event = correction('once', 10);
      await send(event);
      await send(UndoCorrectionEvent(engine.state.game.corrections.single.id));
      await send(event);
      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.game.corrections, hasLength(2));
    },
  );

  test(
    'changed teams block an old financial reversal without overwriting totals',
    () async {
      await start(jeopardy: true);
      await send(correction('one', 20));
      final entry = engine.state.game.corrections.single;
      await send(const AssignTeamEvent(playerId: 'p1', teamId: 'b'));
      final before = engine.state.game;
      await send(UndoCorrectionEvent(entry.id));
      expect(engine.state.game, before);
      expect(engine.state.notice, contains('Teams'));
    },
  );

  test(
    'net question winners exclude a fully reversed positive correction',
    () async {
      await start();
      await send(correction('one', 20));
      final entry = engine.state.game.corrections.single;
      await send(UndoCorrectionEvent(entry.id));
      expect(
        engine.state.game.copyWith(completedQuestionIds: {'q'}).questionWinners,
        isEmpty,
      );
      await send(correction('two', 10));
      expect(
        engine.state.game.copyWith(completedQuestionIds: {'q'}).questionWinners,
        {'q': 'One'},
      );
    },
  );

  test(
    'buzzer round references and undo survive a checkpoint round trip',
    () async {
      await start(buzzer: true, poker: true);
      await buzz();
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      final quiz = Quiz(
        id: 'quiz',
        name: 'Quiz',
        description: 'Recovery fixture',
        category: 'Tests',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        questions: const [_buzzer],
        teams: _teams.values.toList(),
        format: const PokerFormat(startingChips: 100),
      );
      final checkpoint = SessionCheckpoint(
        sessionId: 'session-corrections-1234',
        quiz: quiz,
        game: engine.state.game,
        savedAtMicros: _epoch,
        resumeTokenHashes: {'p1': 'a' * 64, 'p2': 'b' * 64},
      );
      checkpoint.validate();
      final envelope = jsonDecode(checkpoint.encode()) as Map<String, dynamic>;
      final payload =
          jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
      final gameJson = payload['game'] as Map<String, dynamic>;
      final correctionJson =
          (gameJson['corrections'] as List).single as Map<String, dynamic>;
      expect(
        (correctionJson['beforeRound'] as Map).containsKey('question'),
        isFalse,
      );
      final saved = SessionCheckpoint.decode(
        checkpoint.encode(),
        quizDocument: jsonEncode(quiz.toJson()),
      );
      expect(saved.game.corrections, engine.state.game.corrections);
      final restored = QuizEngineBloc(
        restoredGame: saved.pausedGame(),
        now: () => _epoch,
      );
      addTearDown(restored.close);
      restored.add(
        const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
      );
      await pumpEventQueue();
      restored.add(UndoCorrectionEvent(saved.game.corrections.single.id));
      await pumpEventQueue();
      expect(restored.state.game.poker!.chips['a'], 80);
      expect(restored.state.game.round.activePlayerId, 'p1');
      final resaved = SessionCheckpoint(
        sessionId: checkpoint.sessionId,
        quiz: quiz,
        game: restored.state.game,
        savedAtMicros: _epoch,
        resumeTokenHashes: checkpoint.resumeTokenHashes,
      );
      resaved.validate();
    },
  );
}
