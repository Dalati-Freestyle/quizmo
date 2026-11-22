/// Minimum and maximum stakes of the poker format (quiz schema 12).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const question = TrueFalseQuestion(
  id: 'q',
  prompt: 'True?',
  correctAnswer: true,
);
const teams = {
  'a': Team(id: 'a', name: 'A'),
  'b': Team(id: 'b', name: 'B'),
  'c': Team(id: 'c', name: 'C'),
};

Quiz pokerQuiz(PokerFormat format) => Quiz(
  id: 'poker',
  name: 'Poker',
  description: 'Stakes',
  category: 'Tests',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: const [question],
  format: format,
);

void main() {
  group('PokerState stake range', () {
    const limited = PokerState(startingChips: 100, minStake: 10, maxStake: 40);

    test('clamps to the limits and forces all-in below the minimum', () {
      expect(limited.lowestStakeFor(100), 10);
      expect(limited.highestStakeFor(100), 40);
      expect(limited.lowestStakeFor(6), 6);
      expect(limited.highestStakeFor(6), 6);
      expect(limited.allowsStake(0, 100), isFalse);
      expect(limited.allowsStake(9, 100), isFalse);
      expect(limited.allowsStake(41, 100), isFalse);
      expect(limited.allowsStake(25, 100), isTrue);
      expect(limited.allowsStake(6, 6), isTrue);
      expect(limited.allowsStake(5, 6), isFalse);
    });

    test('without limits any stake from 0 to all chips is allowed', () {
      const open = PokerState(startingChips: 100);
      expect(open.allowsStake(0, 100), isTrue);
      expect(open.allowsStake(100, 100), isTrue);
      expect(open.allowsStake(101, 100), isFalse);
    });

    test('survives JSON and reads older snapshots without limits', () {
      expect(PokerState.fromJson(limited.toJson()), limited);
      expect(
        PokerState.fromJson(const {
          'startingChips': 100,
          'chips': <String, Object?>{},
          'wagers': <String, Object?>{},
          'settledTeamIds': <Object?>[],
          'betting': false,
        }),
        const PokerState(startingChips: 100),
      );
    });
  });

  group('engine', () {
    late QuizEngineBloc engine;
    Future<void> send(QuizEngineEvent event) async {
      engine.add(event);
      await pumpEventQueue();
    }

    Future<void> wager(String player, int amount) => send(
      PlacePokerWagerEvent(playerId: player, questionId: 'q', wager: amount),
    );

    setUp(() async {
      engine = QuizEngineBloc(
        questionBank: const [question],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 100,
        pokerMinStake: 10,
        pokerMaxStake: 40,
        now: () => 1000,
      );
      for (final (id, team) in [('p1', 'a'), ('p2', 'b'), ('p3', 'c')]) {
        await send(PlayerJoinedEvent(Player(id: id, name: id, teamId: team)));
      }
    });
    Future<void> start() => send(const StartRoundEvent('q'));
    tearDown(() => engine.close());

    test('rejects stakes outside the limits', () async {
      await start();
      await wager('p1', 0);
      await wager('p1', 5);
      await wager('p1', 41);
      expect(engine.state.game.poker!.wagers, isEmpty);
      await wager('p1', 40);
      await wager('p2', 10);
      expect(engine.state.game.poker!.wagers, {'a': 40, 'b': 10});
      expect(engine.state.game.poker!.chips['a'], 60);
    });

    test('closing the betting raises missing stakes to the minimum', () async {
      await start();
      await wager('p1', 30);
      await send(const OpenPokerAnswersEvent());
      final poker = engine.state.game.poker!;
      expect(poker.betting, isFalse);
      expect(poker.wagers, {'a': 30, 'b': 10, 'c': 10});
      expect(poker.chips, {'a': 70, 'b': 90, 'c': 90});
    });

    test('a team short of the minimum goes all-in', () async {
      await send(
        const CorrectScoreEvent(
          requestId: 'r',
          teamId: 'b',
          delta: -96,
          reason: 'test',
        ),
      );
      expect(engine.state.game.poker!.chips['b'], 4);
      await start();
      await wager('p2', 3);
      expect(engine.state.game.poker!.wagers['b'], isNull);
      await wager('p2', 4);
      expect(engine.state.game.poker!.wagers['b'], 4);
    });

    test('reset keeps the limits', () async {
      await send(const ResetGameEvent());
      final poker = engine.state.game.poker!;
      expect((poker.minStake, poker.maxStake), (10, 40));
    });

    test('rejects an impossible configuration', () {
      expect(
        () => QuizEngineBloc(
          teams: teams,
          pokerStartingChips: 100,
          pokerMinStake: 50,
          pokerMaxStake: 20,
        ),
        throwsArgumentError,
      );
    });
  });

  group('quiz file', () {
    test('round-trips the stake limits in the latest schema', () {
      final quiz = pokerQuiz(
        const PokerFormat(startingChips: 200, minStake: 5, maxStake: 50),
      );
      final exported = exportQuizJson(quiz);
      final json = jsonDecode(exported) as Map<String, Object?>;
      expect(json['schemaVersion'], 12);
      expect(json['format'], {
        'type': 'poker',
        'startingChips': 200,
        'minStake': 5,
        'maxStake': 50,
      });
      expect(parseQuizImport(exported).format, quiz.format);
    });

    test('a schema 11 poker file imports without limits', () {
      final quiz = parseQuizImport(
        File('test/fixtures/quiz_v11_poker.quizmo.json').readAsStringSync(),
      );
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      expect(quiz.format, const PokerFormat(startingChips: 150));
      expect(quiz.questions, hasLength(3));
    });

    test('a schema 11 file cannot carry stake limits', () {
      final json = jsonDecode(
        File('test/fixtures/quiz_v11_poker.quizmo.json').readAsStringSync(),
      ) as Map<String, Object?>;
      json['format'] = {'type': 'poker', 'startingChips': 150, 'minStake': 5};
      expect(
        () => parseQuizImport(jsonEncode(json)),
        throwsA(isA<QuizImportException>()),
      );
    });

    test('validates the limits against the starting chips', () {
      for (final format in const [
        PokerFormat(startingChips: 100, minStake: -1),
        PokerFormat(startingChips: 100, minStake: 101),
        PokerFormat(startingChips: 100, maxStake: 0),
        PokerFormat(startingChips: 100, minStake: 20, maxStake: 10),
        PokerFormat(startingChips: 100, maxStake: 101),
      ]) {
        expect(
          pokerQuiz(format).validationErrors(),
          isNotEmpty,
          reason: '$format',
        );
      }
      expect(
        pokerQuiz(
          const PokerFormat(startingChips: 100, minStake: 10, maxStake: 10),
        ).validationErrors(),
        isEmpty,
      );
    });
  });
}
