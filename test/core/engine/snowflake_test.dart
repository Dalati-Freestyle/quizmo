import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';

const trueFalse = TrueFalseQuestion(
  id: 'tf',
  prompt: 'Pineapple belongs on pizza.',
  timeLimit: Duration.zero,
  scoringRule: FixedPointsRule(correctPoints: 12),
);

const choice = MultipleChoiceQuestion(
  id: 'mc',
  prompt: 'Best season?',
  timeLimit: Duration.zero,
  scoringRule: FixedPointsRule(correctPoints: 12),
  options: [
    AnswerOption(id: 'a', label: 'Spring'),
    AnswerOption(id: 'b', label: 'Summer'),
    AnswerOption(id: 'c', label: 'Autumn'),
    AnswerOption(id: 'd', label: 'Winter'),
  ],
);

const ordering = OrderingQuestion(
  id: 'order',
  prompt: 'Rank them',
  timeLimit: Duration.zero,
  items: [
    AnswerOption(id: 'x', label: 'X'),
    AnswerOption(id: 'y', label: 'Y'),
  ],
);

const matching = MatchingQuestion(
  id: 'match',
  prompt: 'Pair them',
  timeLimit: Duration.zero,
  leftItems: [
    AnswerOption(id: 'l1', label: 'L1'),
    AnswerOption(id: 'l2', label: 'L2'),
  ],
  rightItems: [
    AnswerOption(id: 'r1', label: 'R1'),
    AnswerOption(id: 'r2', label: 'R2'),
  ],
);

TrueFalseAnswer truth(String player, bool value) => TrueFalseAnswer(
  playerId: player,
  questionId: 'tf',
  clientTimestampMicros: 1000001,
  clockOffsetMicros: 0,
  value: value,
);

MultipleChoiceAnswer pick(String player, String option) => MultipleChoiceAnswer(
  playerId: player,
  questionId: 'mc',
  clientTimestampMicros: 1000001,
  clockOffsetMicros: 0,
  optionId: option,
);

Quiz snowflakeQuiz({
  SnowflakeScoring scoring = SnowflakeScoring.winnerOnly,
  List<Question> questions = const [trueFalse, choice, ordering, matching],
}) => Quiz(
  id: 'quiz',
  name: 'Snowflakes',
  description: 'Rarest answer wins',
  category: 'Testing',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  format: SnowflakeFormat(scoring: scoring),
  questions: questions,
);

Future<QuizEngineBloc> play(
  Question question,
  List<AnswerSubmission> answers, {
  SnowflakeScoring scoring = SnowflakeScoring.winnerOnly,
  bool reveal = true,
}) async {
  final engine = QuizEngineBloc(
    questionBank: [question],
    snowflakeScoring: scoring,
    now: () => 1000000,
  );
  addTearDown(engine.close);
  for (final answer in answers) {
    engine.add(
      PlayerJoinedEvent(Player(id: answer.playerId, name: answer.playerId)),
    );
  }
  // One more player who never answers keeps the round open.
  engine.add(const PlayerJoinedEvent(Player(id: 'silent', name: 'silent')));
  await pumpEventQueue();
  engine.add(StartRoundEvent(question.id));
  await pumpEventQueue();
  for (final answer in answers) {
    engine.add(SubmitAnswerEvent(answer));
  }
  await pumpEventQueue();
  if (reveal) {
    engine.add(const RevealRoundEvent());
    await pumpEventQueue();
  }
  return engine;
}

void main() {
  group('snowflakeShares', () {
    test('only the rarest answer scores when not graded', () {
      expect(
        snowflakeShares({
          'a': 'yes',
          'b': 'yes',
          'c': 'yes',
          'd': 'no',
          'e': 'no',
          'f': 'no',
          'g': 'no',
        }, graded: false),
        {'a': 1, 'b': 1, 'c': 1, 'd': 0, 'e': 0, 'f': 0, 'g': 0},
      );
    });

    test('graded shares fall per step until the most common gets nothing', () {
      final shares = snowflakeShares({
        'a': 'w',
        'b': 'x',
        'c': 'x',
        'd': 'y',
        'e': 'y',
        'f': 'y',
        'g': 'z',
        'h': 'z',
        'i': 'z',
        'j': 'z',
      }, graded: true);
      expect(shares['a'], 1);
      expect(shares['b'], closeTo(2 / 3, 1e-9));
      expect(shares['d'], closeTo(1 / 3, 1e-9));
      expect(shares['g'], 0);
      // Without grading the runners-up get nothing.
      final winnerOnly = snowflakeShares({
        'a': 'w',
        'b': 'x',
        'c': 'x',
        'd': 'y',
        'e': 'y',
        'f': 'y',
      }, graded: false);
      expect(winnerOnly, {'a': 1, 'b': 0, 'c': 0, 'd': 0, 'e': 0, 'f': 0});
    });

    test('equally rare answers share a step', () {
      for (final graded in [true, false]) {
        expect(
          snowflakeShares({
            'a': 'x',
            'b': 'y',
            'c': 'z',
            'd': 'z',
          }, graded: graded),
          {'a': 1, 'b': 1, 'c': 0, 'd': 0},
        );
        // Everyone is equally unique.
        expect(snowflakeShares({'a': 'x', 'b': 'y'}, graded: graded), {
          'a': 1,
          'b': 1,
        });
      }
    });

    test('nobody scores when everyone agrees; a lone answer scores', () {
      for (final graded in [true, false]) {
        expect(snowflakeShares({'a': 'x', 'b': 'x'}, graded: graded), {
          'a': 0,
          'b': 0,
        });
        expect(snowflakeShares({'a': 'x'}, graded: graded), {'a': 1});
        expect(snowflakeShares({}, graded: graded), isEmpty);
      }
    });
  });

  group('uniqueness keys', () {
    test('only kinds with a finite answer set support them', () {
      for (final question in <Question>[
        trueFalse,
        choice,
        ordering,
        matching,
      ]) {
        expect(question.supportsUniqueness, isTrue, reason: question.id);
      }
      for (final question in const <Question>[
        BuzzerQuestion(id: 'b', prompt: 'b'),
        ShortAnswerQuestion(id: 's', prompt: 's'),
        EstimationQuestion(id: 'e', prompt: 'e'),
      ]) {
        expect(question.supportsUniqueness, isFalse, reason: question.id);
      }
    });

    test('equal answers share a key whatever the selection order', () {
      const multi = MultipleChoiceQuestion(
        id: 'mc',
        prompt: 'p',
        allowMultipleAnswers: true,
        options: [
          AnswerOption(id: 'a', label: 'A'),
          AnswerOption(id: 'b', label: 'B'),
        ],
      );
      MultipleChoiceAnswer both(List<String> ids) => MultipleChoiceAnswer(
        playerId: 'p',
        questionId: 'mc',
        clientTimestampMicros: 0,
        clockOffsetMicros: 0,
        optionIds: ids,
      );
      expect(
        multi.uniquenessKey(both(['a', 'b'])),
        multi.uniquenessKey(both(['b', 'a'])),
      );
      expect(
        multi.uniquenessKey(both(['a'])),
        isNot(multi.uniquenessKey(both(['a', 'b']))),
      );
      expect(multi.uniquenessKey(both(['nope'])), isNull);

      OrderingAnswer order(List<String> ids) => OrderingAnswer(
        playerId: 'p',
        questionId: 'order',
        clientTimestampMicros: 0,
        clockOffsetMicros: 0,
        itemIds: ids,
      );
      expect(
        ordering.uniquenessKey(order(['x', 'y'])),
        isNot(ordering.uniquenessKey(order(['y', 'x']))),
      );

      MatchingAnswer pairs(Map<String, String> value) => MatchingAnswer(
        playerId: 'p',
        questionId: 'match',
        clientTimestampMicros: 0,
        clockOffsetMicros: 0,
        pairs: value,
      );
      expect(
        matching.uniquenessKey(pairs({'l1': 'r1', 'l2': 'r2'})),
        matching.uniquenessKey(pairs({'l2': 'r2', 'l1': 'r1'})),
      );
      expect(
        matching.uniquenessKey(pairs({'l1': 'r1', 'l2': 'r2'})),
        isNot(matching.uniquenessKey(pairs({'l1': 'r2', 'l2': 'r1'}))),
      );
      expect(trueFalse.uniquenessKey(order(['x', 'y'])), isNull);
    });
  });

  group('engine', () {
    test('3 of 7 say true: only those three score', () async {
      final engine = await play(trueFalse, [
        for (final id in ['a', 'b', 'c']) truth(id, true),
        for (final id in ['d', 'e', 'f', 'g']) truth(id, false),
      ]);
      final game = engine.state.game;
      expect(game.round.status, RoundStatus.revealed);
      for (final id in ['a', 'b', 'c']) {
        expect(game.scores.scoreOf(id), 12, reason: id);
      }
      for (final id in ['d', 'e', 'f', 'g', 'silent']) {
        expect(game.scores.scoreOf(id), 0, reason: id);
      }
      expect(game.round.accuracyFor(truth('a', true)), 1);
      expect(game.round.accuracyFor(truth('d', false)), 0);
    });

    test('graded: the runner-up gets a share, the crowd nothing', () async {
      final answers = [
        pick('a', 'a'),
        pick('b', 'b'),
        pick('c', 'b'),
        pick('d', 'c'),
        pick('e', 'c'),
        pick('f', 'c'),
      ];
      final graded = await play(
        choice,
        answers,
        scoring: SnowflakeScoring.graded,
      );
      expect(graded.state.game.scores.scoreOf('a'), 12);
      expect(graded.state.game.scores.scoreOf('b'), 6);
      expect(graded.state.game.scores.scoreOf('d'), 0);
      expect(graded.state.game.round.snowflakeGroups.map((g) => g.playerIds), [
        ['a'],
        ['b', 'c'],
        ['d', 'e', 'f'],
      ]);

      final winnerOnly = await play(choice, answers);
      expect(winnerOnly.state.game.scores.scoreOf('a'), 12);
      expect(winnerOnly.state.game.scores.scoreOf('b'), 0);
    });

    test('nobody scores when everyone gives the same answer', () async {
      final engine = await play(trueFalse, [
        truth('a', true),
        truth('b', true),
      ]);
      expect(engine.state.game.scores.scoreOf('a'), 0);
      expect(engine.state.game.scores.scoreOf('b'), 0);
    });

    test(
      'guests see no answers before the reveal, only their number',
      () async {
        final engine = await play(trueFalse, [
          truth('a', true),
          truth('b', false),
        ], reveal: false);
        final open = engine.state.game.redactedForPlayers();
        expect(open.snowflake, SnowflakeScoring.winnerOnly);
        expect(open.round.answers, isEmpty);
        expect(open.round.answerCount, 2);
        expect(open.round.snowflakeGroups, isEmpty);
        expect(open.round.accuracyFor(truth('a', true)), isNull);
        // The snapshot survives the wire.
        expect(GameState.fromJson(open.toJson()), open);

        engine.add(const RevealRoundEvent());
        await pumpEventQueue();
        final revealed = engine.state.game.redactedForPlayers();
        expect(revealed.round.answers, hasLength(2));
        expect(revealed.round.hiddenAnswerCount, 0);
        expect(revealed.round.snowflakeGroups, hasLength(2));
      },
    );

    test('a reset keeps the format', () async {
      final engine = await play(trueFalse, [truth('a', true)]);
      engine.add(const ResetGameEvent());
      await pumpEventQueue();
      expect(engine.state.game.snowflake, SnowflakeScoring.winnerOnly);
      engine.add(const StartRoundEvent('tf'));
      await pumpEventQueue();
      expect(engine.state.game.round.snowflake, SnowflakeScoring.winnerOnly);
    });

    test('bots give valid answers without a solution', () {
      for (final question in <Question>[
        trueFalse,
        choice,
        ordering,
        matching,
      ]) {
        final keys = {
          for (var variant = 0; variant < 4; variant++)
            question.uniquenessKey(
              botAnswer(
                question,
                playerId: 'bot',
                timestamp: 1,
                correct: true,
                variant: variant,
              ),
            ),
        };
        expect(keys, isNot(contains(null)), reason: question.id);
        expect(keys.length, greaterThan(1), reason: question.id);
      }
    });
  });

  group('quiz file', () {
    test('a snowflake quiz needs no solutions and round trips', () {
      for (final scoring in SnowflakeScoring.values) {
        final quiz = snowflakeQuiz(scoring: scoring);
        expect(quiz.validationErrors(), isEmpty);
        final contents = exportQuizJson(quiz);
        final json = jsonDecode(contents) as Map<String, dynamic>;
        expect(json['schemaVersion'], 10);
        expect(json['format'], {'type': 'snowflake', 'scoring': scoring.name});
        expect(parseQuizImport(contents), quiz);
      }
    });

    test('a file with solutions is normalised on import', () {
      final json = snowflakeQuiz().toJson();
      json['questions'] = [
        const TrueFalseQuestion(
          id: 'tf',
          prompt: 'p',
          correctAnswer: true,
          adminNotes: 'note',
        ).toJson(),
      ];
      final quiz = parseQuizImport(jsonEncode(json));
      expect(quiz.questions.single.hasSolution, isFalse);
      expect(quiz.questions.single.adminNotes, 'note');
    });

    test('only deterministic kinds and no stored solutions are valid', () {
      expect(
        snowflakeQuiz(
          questions: const [BuzzerQuestion(id: 'b', prompt: 'Buzz')],
        ).validationErrors(),
        [contains('Biggest Snowflake unterstützt die Frage "b" nicht')],
      );
      expect(
        snowflakeQuiz(
          questions: const [
            TrueFalseQuestion(id: 'tf', prompt: 'p', correctAnswer: true),
          ],
        ).validationErrors(),
        [contains('speichert keine Lösung')],
      );
      // Other formats still need their solutions.
      expect(
        snowflakeQuiz()
            .copyWith(format: const StandardFormat())
            .validationErrors(),
        isNotEmpty,
      );
    });

    test('invalid snowflake files never reach the library', () async {
      final repository = InMemoryQuizRepository();
      final unknownScoring = snowflakeQuiz().toJson()
        ..['format'] = {'type': 'snowflake', 'scoring': 'everyone'};
      final withBuzzer = snowflakeQuiz().toJson()
        ..['questions'] = [
          const BuzzerQuestion(id: 'b', prompt: 'Buzz').toJson(),
        ];
      // The format does not exist in schema 9.
      final tooOld = snowflakeQuiz().toJson()..['schemaVersion'] = 9;
      for (final json in [unknownScoring, withBuzzer, tooOld]) {
        await expectLater(
          importQuiz(
            contents: jsonEncode(json),
            repository: repository,
            createId: () => 'new',
          ),
          throwsA(isA<QuizImportException>()),
        );
      }
      expect(await repository.loadAll(), isEmpty);
    });

    test('a schema 9 file still imports and is saved as schema 10', () {
      final contents = File.fromUri(
        Directory.current.uri.resolve(
          'test/fixtures/quiz_v9_poker.quizmo.json',
        ),
      ).readAsStringSync();
      final quiz = parseQuizImport(contents);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      expect(quiz.format, const PokerFormat(startingChips: 150));
      expect(quiz.questions, hasLength(3));
      expect(quiz.questions.every((q) => q.hasSolution), isTrue);
      expect(quiz.teams.single.name, 'Alpha');
      expect(
        jsonDecode(exportQuizJson(quiz))['schemaVersion'],
        Quiz.currentSchemaVersion,
      );
    });
  });
}
