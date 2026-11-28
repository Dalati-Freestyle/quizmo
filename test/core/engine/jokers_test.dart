/// Poker jokers "Kredit" and "Zwangseinsatz" (quiz schema 12).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const question = TrueFalseQuestion(
  id: 'q',
  prompt: 'True?',
  category: 'Deutschland',
  correctAnswer: true,
);
const second = TrueFalseQuestion(
  id: 'q2',
  prompt: 'Again?',
  correctAnswer: true,
);
const teams = {
  'a': Team(id: 'a', name: 'A'),
  'b': Team(id: 'b', name: 'B'),
  'c': Team(id: 'c', name: 'C'),
};
const credit = CreditJoker();
const attack = ForcedStakeJoker();

void main() {
  group('pokerSettlement', () {
    test('without a joker a miss loses the stake', () {
      expect(pokerSettlement(wager: 3, isCorrect: true), 6);
      expect(pokerSettlement(wager: 3, isCorrect: false), 0);
    });

    test('a credit limits the loss of a miss', () {
      expect(pokerSettlement(wager: 3, isCorrect: false, covering: credit), 2);
      expect(pokerSettlement(wager: 3, isCorrect: true, covering: credit), 6);
      expect(pokerSettlement(wager: 0, isCorrect: false, covering: credit), 0);
    });

    test('a forced stake doubles the loss of a miss only', () {
      expect(pokerSettlement(wager: 3, isCorrect: false, covering: attack), -3);
      expect(pokerSettlement(wager: 3, isCorrect: true, covering: attack), 6);
    });
  });

  group('engine', () {
    late QuizEngineBloc engine;
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    Future<void> wager(String player, int amount, {String id = 'q'}) => send(
      PlacePokerWagerEvent(playerId: player, questionId: id, wager: amount),
    );
    Future<void> answer(String player, bool value, {String id = 'q'}) => send(
      SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: player,
          questionId: id,
          clientTimestampMicros: 1000,
          clockOffsetMicros: 0,
          value: value,
        ),
      ),
    );
    Map<String, int> chips() => engine.state.game.poker!.chips;

    setUp(() async {
      engine = QuizEngineBloc(
        questionBank: const [question, second],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 15,
        pokerMinStake: 1,
        pokerMaxStake: 3,
        jokers: const [credit, attack],
        now: () => 1000,
      );
      for (final (id, team) in [('p1', 'a'), ('p2', 'b'), ('p3', 'c')]) {
        await send(PlayerJoinedEvent(Player(id: id, name: id, teamId: team)));
      }
      await send(const StartRoundEvent('q'));
    });
    tearDown(() => engine.close());

    Future<void> attackOn(String target, {String by = 'a'}) => send(
      UseJokerEvent(jokerId: 'forcedStake', teamId: by, targetTeamId: target),
    );
    Future<void> reveal() => send(const RevealPokerQuestionEvent());

    test('a question starts with its category only', () async {
      final game = engine.state.game;
      expect(game.poker!.questionHidden, isTrue);
      expect(game.poker!.category, 'Deutschland');
      final snapshot = game.redactedForPlayers();
      expect(snapshot.round.question, isNull);
      expect(snapshot.poker!.category, 'Deutschland');
      expect(snapshot.round.startedAtHostMicros, isNotNull);
      // No stakes, no defensive joker and no answers before the reveal.
      await wager('p1', 2);
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'a'));
      await send(const OpenPokerAnswersEvent());
      expect(engine.state.game.poker!.wagers, isEmpty);
      expect(engine.state.game.jokers!.plays, isEmpty);
      expect(engine.state.game.poker!.betting, isTrue);
      await reveal();
      expect(engine.state.game.poker!.questionHidden, isFalse);
      expect(engine.state.game.redactedForPlayers().round.question, isNotNull);
      // The attack belongs to the category phase.
      await attackOn('b');
      expect(engine.state.game.jokers!.plays, isEmpty);
    });

    test('a credit costs only one coin of a lost stake', () async {
      await reveal();
      await wager('p1', 3);
      await send(const UseJokerEvent(jokerId: 'credit', playerId: 'p1'));
      expect(engine.state.game.jokers!.plays.single.teamId, 'a');
      await send(const OpenPokerAnswersEvent());
      await answer('p1', false);
      await send(const RevealRoundEvent());
      expect(chips()['a'], 14);
      expect(engine.state.game.jokers!.remainingFor('a', credit), 0);
    });

    test('a player plays a joker for the round they see', () async {
      final started = engine.state.game.round.startedAtHostMicros;
      await send(
        UseJokerEvent(
          jokerId: 'forcedStake',
          playerId: 'p1',
          targetTeamId: 'b',
          roundStartedAt: started! + 1,
        ),
      );
      expect(engine.state.game.jokers!.plays, isEmpty);
      await send(
        UseJokerEvent(
          jokerId: 'forcedStake',
          playerId: 'p1',
          targetTeamId: 'b',
          roundStartedAt: started,
        ),
      );
      expect(engine.state.game.jokers!.plays.single.teamId, 'a');
    });

    test('the attack forces the stake, costs the attacker and locks the '
        'target', () async {
      await attackOn('b');
      expect(chips()['a'], 13);
      expect(engine.state.game.poker!.wagers['b'], 3);
      expect(chips()['b'], 12);
      await reveal();
      await wager('p2', 1);
      expect(engine.state.game.poker!.wagers['b'], 3);
      await send(const OpenPokerAnswersEvent());
      await answer('p2', false);
      await send(const RevealRoundEvent());
      // The stake of 3 is gone and 3 more chips: 6 in total.
      expect(chips()['b'], 9);
    });

    test('a correct target wins the usual payout', () async {
      await attackOn('b');
      await reveal();
      await send(const OpenPokerAnswersEvent());
      await answer('p2', true);
      await send(const RevealRoundEvent());
      expect(chips()['b'], 18);
    });

    test('a team takes part in one joker per question only', () async {
      await attackOn('b');
      await attackOn('b', by: 'c');
      await attackOn('a', by: 'c');
      expect(engine.state.game.jokers!.plays, hasLength(1));
      await reveal();
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'b'));
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'a'));
      expect(engine.state.game.jokers!.plays, hasLength(1));
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'c'));
      expect(engine.state.game.jokers!.plays, hasLength(2));
    });

    test('nobody attacks itself and jokers end with the betting', () async {
      await attackOn('a');
      await reveal();
      await send(const OpenPokerAnswersEvent());
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'a'));
      expect(engine.state.game.jokers!.plays, isEmpty);
    });

    test('each joker is used once per team and game', () async {
      await reveal();
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'a'));
      await send(const OpenPokerAnswersEvent());
      await send(const RevealRoundEvent());
      await send(const StartRoundEvent('q2'));
      expect(engine.state.game.jokers!.plays, isEmpty);
      await reveal();
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'a'));
      expect(engine.state.game.jokers!.plays, isEmpty);
      await send(const UseJokerEvent(jokerId: 'credit', teamId: 'b'));
      expect(engine.state.game.jokers!.plays, hasLength(1));
    });

    test('the host can take a joker back while betting', () async {
      await attackOn('b');
      await send(const RevokeJokerEvent(teamId: 'a', jokerId: 'forcedStake'));
      expect(chips(), {'a': 15, 'b': 15, 'c': 15});
      expect(engine.state.game.poker!.wagers, isEmpty);
      expect(engine.state.game.jokers!.remainingFor('a', attack), 1);
    });

    test('ending the game early returns the jokers and their price', () async {
      await attackOn('b');
      await send(const FinishQuizEvent(early: true));
      expect(chips(), {'a': 15, 'b': 15, 'c': 15});
      expect(engine.state.game.jokers!.remainingFor('a', attack), 1);
    });

    test('reset restores every joker', () async {
      await attackOn('b');
      await send(const ResetGameEvent());
      final jokers = engine.state.game.jokers!;
      expect(jokers.plays, isEmpty);
      expect(jokers.remainingFor('a', attack), 1);
    });

    test('jokers survive the guest snapshot and JSON', () async {
      await attackOn('b');
      final snapshot = engine.state.game.redactedForPlayers();
      expect(snapshot.jokers, engine.state.game.jokers);
      expect(
        GameState.fromJson(jsonDecode(jsonEncode(snapshot.toJson())) as JsonMap)
            .jokers,
        snapshot.jokers,
      );
    });
  });

  test(
    'without a joker before the reveal there is no category phase',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [question],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 15,
        jokers: const [credit],
      );
      addTearDown(engine.close);
      engine.add(const StartRoundEvent('q'));
      await pumpEventQueue();
      expect(engine.state.game.poker!.betting, isTrue);
      expect(engine.state.game.poker!.questionHidden, isFalse);
    },
  );

  test('poker jokers need a poker session', () {
    expect(
      () => QuizEngineBloc(teams: teams, jokers: const [credit]),
      throwsArgumentError,
    );
  });

  group('quiz file', () {
    Quiz quiz(QuizFormat format, List<Joker> jokers) => Quiz(
      id: 'quiz',
      name: 'Jokers',
      description: 'Jokers',
      category: 'Tests',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [question],
      format: format,
      jokers: jokers,
    );

    test('round-trips the jokers', () {
      final original = quiz(const PokerFormat(startingChips: 15), const [
        CreditJoker(maxLoss: 2),
        ForcedStakeJoker(stake: 4, cost: 1, lossFactor: 3, usesPerTeam: 2),
      ]);
      expect(parseQuizImport(exportQuizJson(original)), original);
    });

    test('a quiz without jokers has none', () {
      final plain = quiz(const PokerFormat(), const []);
      final restored = parseQuizImport(exportQuizJson(plain));
      expect(restored.jokers, isEmpty);
    });

    test('poker jokers are rejected in other formats', () {
      expect(
        quiz(const StandardFormat(), const [credit]).validationErrors(),
        isNotEmpty,
      );
      expect(
        quiz(const PokerFormat(), const [credit, credit]).validationErrors(),
        isNotEmpty,
      );
    });
  });
}
