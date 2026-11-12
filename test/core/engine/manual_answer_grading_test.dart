import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/answer_evaluation.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const question = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Hauptstadt?',
  acceptedAnswers: ['Berlin', 'Berlin Stadt'],
  manualGrading: true,
  scoringRule: FirstBuzzerRule(points: 20, penalty: -5, rankDecay: 5),
);
const teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

void main() {
  late QuizEngineBloc engine;
  var now = 1000000;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start({
    Question q = question,
    bool poker = false,
    bool jeopardy = false,
    bool dailyDouble = false,
    List<Question> extraQuestions = const [],
  }) async {
    engine = QuizEngineBloc(
      questionBank: [q, ...extraQuestions],
      teams: teams,
      mode: jeopardy ? const TeamMode() : const SoloMode(),
      pokerStartingChips: poker ? 100 : null,
      jeopardyBoard: jeopardy
          ? JeopardyBoard(
              rowPoints: const [100],
              penalizeWrongAnswers: true,
              allowSteal: true,
              categories: [
                JeopardyCategory(
                  name: 'Test',
                  cells: [
                    JeopardyCell(questionId: 'q', isDailyDouble: dailyDouble),
                  ],
                ),
              ],
            )
          : null,
      now: () => now,
    );
    addTearDown(engine.close);
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Two', teamId: 'b')),
    );
    await send(const StartRoundEvent('q'));
    if (dailyDouble) {
      await send(const PlaceDailyDoubleWagerEvent(50));
    }
    if (poker) {
      for (final id in ['p1', 'p2']) {
        await send(
          PlacePokerWagerEvent(playerId: id, questionId: 'q', wager: 20),
        );
      }
      await send(const OpenPokerAnswersEvent());
    }
  }

  Future<void> answer(String id, String text, {int at = 1100000}) => send(
    SubmitAnswerEvent(
      ShortAnswer(
        playerId: id,
        questionId: engine.state.game.round.question!.id,
        clientTimestampMicros: at + 50000,
        clockOffsetMicros: 50000,
        text: text,
      ),
    ),
  );

  JudgeAnswerEvent verdict(String id, bool correct) => JudgeAnswerEvent(
    playerId: id,
    questionId: engine.state.game.round.question!.id,
    startedAtHostMicros: engine.state.game.round.startedAtHostMicros!,
    wasCorrect: correct,
  );

  setUp(() => now = 1000000);

  test('recommendations distinguish matching, typo and different text', () {
    expect(
      recommendTextAnswer(' BERLIN  ', ['Berlin'], 1),
      TextAnswerRecommendation.exactMatch,
    );
    expect(
      recommendTextAnswer('Berln', ['Bonn', 'Berlin'], 1),
      TextAnswerRecommendation.possibleTypo,
    );
    expect(
      recommendTextAnswer('Berln', ['Berlin'], 0),
      TextAnswerRecommendation.different,
    );
    expect(
      recommendTextAnswer('Hamburg', ['Berlin'], 1),
      TextAnswerRecommendation.different,
    );
    expect(
      recommendTextAnswer('', ['Berlin'], 5),
      TextAnswerRecommendation.different,
    );
  });

  test(
    'all submissions wait for host verdicts and explicit finalization',
    () async {
      await start();
      await answer('p1', 'Hamburg');
      await answer('p2', 'Berlin', at: 1200000);
      expect(engine.state.game.round.status, RoundStatus.locked);
      expect(engine.state.game.round.pendingGradeCount, 2);
      expect(engine.state.game.scores.history, isEmpty);

      await send(const RevealRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.locked);
      expect(engine.state.notice, contains('bewerten'));
      await send(verdict('p2', false));
      await send(const EndRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.locked);
      expect(engine.state.game.scores.history, isEmpty);
      await send(verdict('p1', true));
      expect(engine.state.game.round.pendingGradeCount, 0);
      expect(engine.state.game.scores.history, isEmpty);
      await send(const RevealRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.revealed);
      expect(engine.state.game.scores.byPlayer, {'p1': 20, 'p2': -5});
      expect(
        engine.state.game.round.accuracyFor(
          engine.state.game.round.answers['p1']!,
        ),
        1,
      );
      await send(const RevealRoundEvent());
      await send(verdict('p1', false));
      expect(engine.state.game.scores.history, hasLength(2));
      expect(engine.state.game.scores.scoreOf('p1'), 20);
    },
  );

  test('judging order does not change latency-adjusted ranks', () async {
    await start();
    await answer('p2', 'Berlin', at: 1300000);
    await answer('p1', 'Berln', at: 1100000);
    await send(verdict('p2', true));
    await send(verdict('p1', false));
    await send(verdict('p1', true));
    await send(const EndRoundEvent());
    expect(engine.state.game.scores.byPlayer, {'p1': 20, 'p2': 15});
    expect(engine.state.game.scores.history.first.atHostMicros, 1100000);
  });

  test(
    'speed bonus uses the answer time, not the time spent grading',
    () async {
      await start(
        q: const ShortAnswerQuestion(
          id: 'q',
          prompt: 'Hauptstadt?',
          acceptedAnswers: ['Berlin'],
          manualGrading: true,
          timeLimit: Duration(seconds: 10),
          scoringRule: SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10),
        ),
      );
      await answer('p1', 'Berlin', at: 6000000);
      await send(const EndRoundEvent());
      now = 61000000;
      await send(verdict('p1', true));
      await send(const RevealRoundEvent());
      expect(engine.state.game.scores.scoreOf('p1'), 15);
    },
  );

  test('soft time limits still require manual decisions', () async {
    await start(
      q: Question.fromJson({...question.toJson(), 'softTimeLimit': true}),
    );
    now += const Duration(minutes: 5).inMicroseconds;
    await answer('p1', 'Berlin', at: now);
    await answer('p2', 'Berlin', at: now);
    expect(engine.state.game.round.status, RoundStatus.locked);
    expect(engine.state.game.round.pendingGradeCount, 2);
    expect(engine.state.game.scores.history, isEmpty);
  });

  test(
    'closing early locks submissions until every received answer is judged',
    () async {
      await start();
      await answer('p1', 'Berlin');
      await send(const EndRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.locked);
      await answer('p2', 'Berlin');
      expect(engine.state.game.round.answers.keys, ['p1']);
      await send(const StartRoundEvent('q'));
      await send(const NextQuestionEvent());
      expect(engine.state.game.round.answers.keys, ['p1']);
      await send(verdict('p1', false));
      await send(const EndRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.revealed);
      expect(engine.state.game.scores.scoreOf('p1'), -5);
    },
  );

  test(
    'ignores unknown answers and stale round judgments with a notice',
    () async {
      await start();
      await send(verdict('unknown', true));
      expect(engine.state.game.round.answerVerdicts, isEmpty);
      expect(engine.state.notice, isNotNull);
      await answer('p1', 'Berlin');
      final old = verdict('p1', true);
      await send(const ResetGameEvent());
      now += 1000000;
      await send(const StartRoundEvent('q'));
      await answer('p1', 'Berlin', at: 2100000);
      await send(old);
      expect(engine.state.game.round.answerVerdicts, isEmpty);
      expect(engine.state.notice, isNotNull);
    },
  );

  test('timeout keeps answers available for manual grading', () async {
    await start();
    await answer('p1', 'Berln');
    await send(ExpireRoundEvent('q', now));
    expect(engine.state.game.round.status, RoundStatus.locked);
    await send(verdict('p1', true));
    await send(const RevealRoundEvent());
    expect(engine.state.game.scores.scoreOf('p1'), 20);
  });

  test(
    'player and TV snapshots hide decisions and solutions before reveal',
    () async {
      await start();
      await answer('p1', 'Hamburg');
      await send(verdict('p1', true));
      final hostRound = engine.state.game.round;
      expect(RoundState.fromJson(hostRound.toJson()), hostRound);
      final hidden = GameState.fromJson(
        engine.state.game.redactedForPlayers().toJson(),
      );
      expect(hidden.round.answerVerdicts, isEmpty);
      expect(hidden.round.question!.hasSolution, isFalse);
      expect(hidden.questionBank, isEmpty);
      await send(const EndRoundEvent());
      final revealed = GameState.fromJson(
        engine.state.game.redactedForPlayers().toJson(),
      );
      expect(revealed.round.answerVerdicts, {'p1': 1});
      expect(revealed.round.question!.hasSolution, isTrue);
    },
  );

  test('automatic short answers retain their original behavior', () async {
    await start(
      q: const ShortAnswerQuestion(
        id: 'q',
        prompt: 'Hauptstadt?',
        acceptedAnswers: ['Berlin'],
      ),
    );
    await answer('p1', 'Berln');
    await answer('p2', 'Hamburg');
    expect(engine.state.game.round.status, RoundStatus.revealed);
    expect(engine.state.game.scores.scoreOf('p1'), 10);
    await send(verdict('p1', false));
    expect(engine.state.game.round.answerVerdicts, isEmpty);
  });

  test(
    'Jeopardy waits for grading before scoring and opening a steal',
    () async {
      await start(jeopardy: true);
      await answer('p1', 'Berlin');
      expect(engine.state.game.jeopardy!.isStealRound, isFalse);
      await send(const RevealRoundEvent());
      expect(engine.state.game.jeopardy!.isStealRound, isFalse);
      await send(verdict('p1', false));
      await send(const RevealRoundEvent());
      expect(engine.state.game.scores.scoreOf('p1'), -100);
      expect(engine.state.game.jeopardy!.isStealRound, isTrue);
      expect(engine.state.game.round.answerVerdicts, isEmpty);
      await answer('p2', 'Ungewöhnliche, aber akzeptierte Antwort');
      await send(verdict('p2', true));
      await send(const RevealRoundEvent());
      expect(engine.state.game.scores.scoreOf('p2'), 100);
      expect(engine.state.game.round.status, RoundStatus.revealed);
    },
  );

  test('Daily Double uses the wager and never opens a steal', () async {
    await start(jeopardy: true, dailyDouble: true);
    await answer('p1', 'Berlin');
    await send(verdict('p1', false));
    await send(const RevealRoundEvent());
    expect(engine.state.game.scores.scoreOf('p1'), -50);
    expect(engine.state.game.round.status, RoundStatus.revealed);
    expect(engine.state.game.jeopardy!.isStealRound, isFalse);
  });

  test(
    'poker settles stakes only after all host verdicts are finalized',
    () async {
      await start(poker: true);
      await answer('p1', 'Hamburg');
      await answer('p2', 'Berlin');
      await send(verdict('p1', true));
      expect(engine.state.game.teamScores, {'a': 80, 'b': 80});
      final hidden = engine.state.game.redactedForPlayers();
      expect(hidden.round.answers, isEmpty);
      expect(hidden.round.answerVerdicts, isEmpty);
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 80, 'b': 80});
      await send(verdict('p2', false));
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 120, 'b': 80});
      await send(const EndRoundEvent());
      expect(engine.state.game.teamScores, {'a': 120, 'b': 80});
    },
  );

  test(
    'poker counts only one teammate submission and preserves practice mode',
    () async {
      const next = ShortAnswerQuestion(
        id: 'next',
        prompt: 'Weiter?',
        acceptedAnswers: ['Ja'],
        manualGrading: true,
      );
      await start(
        poker: true,
        extraQuestions: [
          next,
          const ShortAnswerQuestion(
            id: 'practice',
            prompt: 'Übung?',
            acceptedAnswers: ['Ja'],
            manualGrading: true,
          ),
        ],
      );
      await send(
        const PlayerJoinedEvent(Player(id: 'mate', name: 'Mate', teamId: 'a')),
      );
      await answer('p1', 'Berlin');
      await answer('mate', 'Berlin');
      expect(engine.state.game.round.answers, hasLength(1));
      await answer('p2', 'Berlin');
      await send(verdict('p1', false));
      await send(verdict('p2', true));
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 80, 'b': 120});
      await send(const NextQuestionEvent());
      await send(
        const PlacePokerWagerEvent(
          playerId: 'p1',
          questionId: 'next',
          wager: 80,
        ),
      );
      await send(const OpenPokerAnswersEvent());
      await answer('p1', 'Ja');
      await send(verdict('p1', false));
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 0, 'b': 120});

      await send(const NextQuestionEvent());
      await send(
        const PlacePokerWagerEvent(
          playerId: 'p2',
          questionId: 'practice',
          wager: 10,
        ),
      );
      await send(const OpenPokerAnswersEvent());
      await answer('p1', 'Ja');
      await answer('p2', 'Nein');
      await send(verdict('p1', true));
      await send(verdict('p2', false));
      await send(const RevealRoundEvent());
      expect(engine.state.game.teamScores, {'a': 0, 'b': 110});
    },
  );

  test(
    'kicking and merging players retain verdicts only for retained answers',
    () async {
      await start();
      await answer('p1', 'Berlin');
      await send(verdict('p1', true));
      await send(const PlayerLeftEvent('p1'));
      await send(
        const PlayerJoinedEvent(Player(id: 'replacement', name: 'New')),
      );
      await send(
        const MergePlayersEvent(
          sourcePlayerId: 'p1',
          targetPlayerId: 'replacement',
        ),
      );
      expect(engine.state.game.round.answers.keys, ['replacement']);
      expect(engine.state.game.round.answerVerdicts, {'replacement': 1});
      await send(const KickPlayerEvent('replacement'));
      expect(engine.state.game.round.answers, isEmpty);
      expect(engine.state.game.round.answerVerdicts, isEmpty);
      await send(const EndRoundEvent());
      expect(engine.state.game.round.status, RoundStatus.revealed);
    },
  );
}
