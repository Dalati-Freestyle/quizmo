import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';

import '../../support/manual_timers.dart';

const _limit = Duration(seconds: 20);
const _options = [
  AnswerOption(id: 'x', label: 'X'),
  AnswerOption(id: 'y', label: 'Y'),
  AnswerOption(id: 'z', label: 'Z'),
];
const _text = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Capital?',
  acceptedAnswers: ['Berlin'],
  maxEdits: 0,
  timeLimit: _limit,
  scoringRule: SpeedBonusRule(),
);
const _matching = MatchingQuestion(
  id: 'q',
  prompt: 'Match',
  leftItems: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  rightItems: [
    AnswerOption(id: 'x', label: 'X'),
    AnswerOption(id: 'y', label: 'Y'),
  ],
  correctPairs: {'a': 'x', 'b': 'y'},
  timeLimit: _limit,
);

void main() {
  late QuizEngineBloc engine;
  late ManualTimers timers;
  late int startedAt;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start(
    Question question, {
    int? poker,
    JeopardyBoard? board,
    SnowflakeScoring? snowflake,
    Duration grace = const Duration(milliseconds: 500),
    Map<String, String?> players = const {'a1': null, 'b1': null},
  }) async {
    timers = ManualTimers();
    final teams = players.values.whereType<String>().toSet();
    engine = QuizEngineBloc(
      questionBank: [question],
      teams: {for (final id in teams) id: Team(id: id, name: id)},
      mode: teams.isEmpty ? const SoloMode() : const TeamMode(),
      pokerStartingChips: poker,
      jeopardyBoard: board,
      snowflakeScoring: snowflake,
      draftGrace: grace,
      now: () => timers.nowMicros,
      createTimer: timers.create,
    );
    addTearDown(engine.close);
    for (final entry in players.entries) {
      await send(
        PlayerJoinedEvent(
          Player(id: entry.key, name: entry.key, teamId: entry.value),
        ),
      );
    }
    if (board == null) await send(const StartRoundEvent('q'));
    startedAt = engine.state.game.round.startedAtHostMicros ?? 0;
  }

  GameState game() => engine.state.game;

  Future<void> advance(Duration duration) async {
    timers.advance(duration);
    await pumpEventQueue();
  }

  ShortAnswer text(String value, {String player = ''}) => ShortAnswer(
    playerId: player,
    questionId: 'q',
    clientTimestampMicros: timers.nowMicros,
    clockOffsetMicros: 0,
    text: value,
  );

  Future<void> draft(
    String player,
    AnswerSubmission? content, {
    int? at,
    int offset = 0,
    int? round,
  }) => send(
    UpdateDraftEvent(
      AnswerDraft(
        playerId: player,
        questionId: 'q',
        roundStartedAt: round ?? startedAt,
        clientTimestampMicros: (at ?? timers.nowMicros) + offset,
        clockOffsetMicros: offset,
        content: content,
      ),
    ),
  );

  /// Lets the time limit run out and the wait for drafts end.
  Future<void> expire() async {
    await advance(_limit - Duration(microseconds: timers.nowMicros));
    await advance(const Duration(milliseconds: 500));
  }

  group('per kind', () {
    final cases = <String, (Question, AnswerSubmission)>{
      'text': (
        _text,
        const ShortAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          text: 'Berlin',
        ),
      ),
      'estimation': (
        const EstimationQuestion(
          id: 'q',
          prompt: 'E',
          correctValue: 3,
          timeLimit: _limit,
        ),
        const EstimationAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          value: 3,
        ),
      ),
      'ordering': (
        const OrderingQuestion(
          id: 'q',
          prompt: 'O',
          items: _options,
          correctOrder: ['x', 'y', 'z'],
          timeLimit: _limit,
        ),
        const OrderingAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          itemIds: ['x', 'y', 'z'],
        ),
      ),
      'matching': (
        _matching,
        const MatchingAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          pairs: {'a': 'x', 'b': 'y'},
        ),
      ),
      'multi': (
        const MultipleChoiceQuestion(
          id: 'q',
          prompt: 'M',
          options: _options,
          correctOptionIds: ['x', 'y'],
          allowMultipleAnswers: true,
          scoringRule: FixedPointsRule(),
          timeLimit: _limit,
        ),
        const MultipleChoiceAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          optionIds: ['x', 'y'],
        ),
      ),
    };
    for (final MapEntry(key: name, value: (question, content))
        in cases.entries) {
      test('$name counts when time is up', () async {
        await start(question);
        await draft('a1', content);
        expect(game().round.answers, isEmpty);
        await expire();
        expect(game().round.status, RoundStatus.locked);
        expect(game().round.answers.keys, ['a1']);
        expect(game().round.adoptedPlayerIds, {'a1'});
        await send(const RevealRoundEvent());
        expect(game().scores.scoreOf('a1'), greaterThan(0));
        expect(game().round.question!.accuracy(game().round.answers['a1']!), 1);
      });
    }

    test('single choice, true/false and buzzer have no drafts', () async {
      const choice = MultipleChoiceQuestion(
        id: 'q',
        prompt: 'M',
        options: _options,
        correctOptionId: 'x',
        timeLimit: _limit,
      );
      expect(choice.supportsDrafts, isFalse);
      expect(
        const TrueFalseQuestion(id: 'q', prompt: 'T').supportsDrafts,
        isFalse,
      );
      expect(
        const BuzzerQuestion(id: 'q', prompt: 'B').supportsDrafts,
        isFalse,
      );
      await start(choice);
      await draft(
        'a1',
        const MultipleChoiceAnswer(
          playerId: '',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          optionId: 'x',
        ),
      );
      await expire();
      expect(game().round.answers, isEmpty);
    });

    test('incomplete pairs count as wrong, not in snowflake', () async {
      final partial = const MatchingAnswer(
        playerId: '',
        questionId: 'q',
        clientTimestampMicros: 0,
        clockOffsetMicros: 0,
        pairs: {'a': 'x'},
      );
      await start(_matching);
      await draft('a1', partial);
      await expire();
      expect((game().round.answers['a1']! as MatchingAnswer).pairs, {'a': 'x'});
      await send(const RevealRoundEvent());
      expect(game().scores.scoreOf('a1'), 0);

      await start(
        _matching.withoutSolution(),
        snowflake: SnowflakeScoring.winnerOnly,
      );
      await draft('a1', partial);
      await expire();
      expect(game().round.answers, isEmpty);
    });
  });

  test('a sent answer always wins, the speed bonus is lost', () async {
    await start(_text);
    await draft('a1', text('Berlin'));
    await draft('b1', text('Berlin'));
    await send(SubmitAnswerEvent(text('Bonn', player: 'a1')));
    await draft('a1', text('Berlin'));
    await expire();
    await send(const RevealRoundEvent());
    expect((game().round.answers['a1']! as ShortAnswer).text, 'Bonn');
    expect(game().round.adoptedPlayerIds, {'b1'});
    expect(game().round.acceptedElapsedMicros['b1'], _limit.inMicroseconds);
    expect(
      game().scores.scoreOf('b1'),
      const SpeedBonusRule()
          .evaluate(
            const ScoringContext(
              isCorrect: true,
              elapsed: _limit,
              timeLimit: _limit,
              rank: 0,
            ),
          )
          .points,
    );
    final report = SessionReport.fromGame(game(), title: 'x');
    expect(
      report.answers.firstWhere((a) => a.playerId == 'b1').adopted,
      isTrue,
    );
    final protocol = buildGameProtocol(game(), title: 'x');
    expect(
      protocol.questions.single.answers
          .firstWhere((a) => a.playerId == 'b1')
          .adopted,
      isTrue,
    );
  });

  test('time bounds: only input from before the end counts', () async {
    await start(_text);
    await advance(const Duration(seconds: 19));
    await draft('a1', text('Bonn'));
    await advance(const Duration(seconds: 1));
    expect(game().round.status, RoundStatus.locked);
    // Under way when time ran out.
    await advance(const Duration(milliseconds: 200));
    await draft('a1', text('Berlin'), at: 19900000);
    // Typed afterwards, or claimed to be earlier than the round.
    await draft('b1', text('Berlin'));
    await draft('b1', text('Berlin'), at: startedAt - 1);
    await advance(const Duration(milliseconds: 300));
    expect((game().round.answers['a1']! as ShortAnswer).text, 'Berlin');
    expect(game().round.answers.keys, ['a1']);
    // After the wait nothing is accepted any more.
    await draft('b1', text('Berlin'), at: 19800000);
    await send(const RevealRoundEvent());
    expect(game().round.answers.keys, ['a1']);
  });

  test('a clock that runs ahead is corrected or rejected', () async {
    await start(_text);
    await draft('a1', text('Berlin'), offset: 5000000);
    expect(engine.draftOf('a1')!.hostTimestampMicros, timers.nowMicros);
    await draft('b1', text('Berlin'), at: timers.nowMicros + 1000000);
    expect(engine.draftOf('b1'), isNull);
  });

  test('clearing withdraws a draft; disconnecting keeps it', () async {
    await start(_text);
    await draft('a1', text('Berlin'));
    await advance(const Duration(seconds: 1));
    await draft('a1', null);
    await draft('b1', text('Berlin'));
    await send(const PlayerLeftEvent('b1'));
    await expire();
    expect(game().round.answers.keys, ['b1']);
  });

  test(
    'a team counts the draft edited last, never the latest arrival',
    () async {
      await start(
        _text,
        players: const {'a1': 'a', 'a2': 'a', 'a3': 'a', 'b1': 'b'},
      );
      await advance(const Duration(seconds: 5));
      await draft('a2', text('late'), at: 4000000);
      await draft('a1', text('early'), at: 3000000);
      await draft('a3', text('cleared'), at: 4500000);
      await draft('a3', null, at: 4600000);
      await expire();
      expect((game().round.answers.values.single as ShortAnswer).text, 'late');
      expect(playerAnswersOf(game(), 'a1').isAdopted, isTrue);
      expect(playerAnswersOf(game(), 'b1').isAdopted, isFalse);
    },
  );

  test('the host ends a round without a limit: drafts count', () async {
    const question = ShortAnswerQuestion(
      id: 'q',
      prompt: 'Q',
      acceptedAnswers: ['Berlin'],
      timeLimit: Duration.zero,
      hints: [QuestionHint(text: 'h', cost: 4)],
    );
    for (final end in [const RevealRoundEvent(), const EndRoundEvent()]) {
      await start(question);
      await draft('a1', text('Berlin'));
      await advance(const Duration(seconds: 1));
      await send(ShowHintEvent(questionId: 'q', shownHints: 0));
      await advance(const Duration(seconds: 1));
      await send(end);
      expect(game().round.status, RoundStatus.locked);
      await advance(const Duration(milliseconds: 500));
      expect(game().round.status, RoundStatus.revealed);
      expect(game().scores.scoreOf('a1'), 6, reason: 'all shown hints cost');
    }
  });

  test('drafts never end a round and never enter the game state', () async {
    await start(_text);
    final before = game();
    await draft('a1', text('Geheim'));
    await draft('b1', text('Geheim'));
    expect(identical(game(), before), isTrue);
    expect('${game().toJson()}', isNot(contains('Geheim')));
  });

  test('manual grading gets the adopted answer to judge', () async {
    await start(
      const ShortAnswerQuestion(
        id: 'q',
        prompt: 'Q',
        acceptedAnswers: ['x'],
        manualGrading: true,
        timeLimit: _limit,
      ),
    );
    await draft('a1', text('maybe'));
    await expire();
    expect(game().round.pendingGradeCount, 1);
    expect(RoundState.fromJson(game().round.toJson()).adoptedPlayerIds, {'a1'});
  });

  test('jeopardy scores the draft before it offers a steal', () async {
    const board = JeopardyBoard(
      rowPoints: [100],
      categories: [
        JeopardyCategory(
          name: 'C',
          cells: [JeopardyCell(questionId: 'q')],
        ),
      ],
    );
    for (final (value, steals) in [('Berlin', false), ('Bonn', true)]) {
      await start(_text, board: board, players: const {'a1': 'a', 'b1': 'b'});
      await send(const StartGameEvent());
      await send(const SelectJeopardyCellEvent('q'));
      startedAt = game().round.startedAtHostMicros!;
      await draft('b1', text('Berlin'));
      await draft('a1', text(value));
      await expire();
      expect(game().jeopardy!.isStealRound, steals);
      if (steals) {
        // Nothing is carried over into the steal round.
        expect(engine.draftOf('a1'), isNull);
        expect(game().round.answers, isEmpty);
      } else {
        expect((game().round.answers['a1']! as ShortAnswer).text, 'Berlin');
      }
    }
  });

  test('poker settles drafts; teams without a stake are left out', () async {
    await start(_text, poker: 100, players: const {'a1': 'a', 'b1': 'b'});
    await send(
      const PlacePokerWagerEvent(playerId: 'a1', questionId: 'q', wager: 30),
    );
    await draft('a1', text('Berlin'));
    expect(engine.draftOf('a1'), isNull, reason: 'still betting');
    await send(const OpenPokerAnswersEvent());
    startedAt = game().round.startedAtHostMicros!;
    await draft('a1', text('Berlin'));
    await draft('b1', text('Berlin'));
    await expire();
    await send(const RevealRoundEvent());
    expect(game().poker!.chips, {'a': 130, 'b': 100});
  });

  test('a draft of another round or question is ignored', () async {
    await start(_text);
    await draft('a1', text('Berlin'), round: startedAt + 1);
    expect(engine.draftOf('a1'), isNull);
  });

  test('the wire format round-trips', () {
    const message = DraftMessage(
      AnswerDraft(
        playerId: 'p',
        questionId: 'q',
        roundStartedAt: 1,
        clientTimestampMicros: 2,
        clockOffsetMicros: 3,
        content: MatchingAnswer(
          playerId: 'p',
          questionId: 'q',
          clientTimestampMicros: 2,
          clockOffsetMicros: 3,
          pairs: {'a': 'x'},
        ),
      ),
    );
    expect(ClientMessage.decode(message.encode()), message);
  });
}
