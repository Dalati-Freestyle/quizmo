import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';

import '../../support/manual_timers.dart';

const _text = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Capital?',
  acceptedAnswers: ['Berlin'],
  maxEdits: 0,
  timeLimit: Duration(seconds: 30),
);

void main() {
  late QuizEngineBloc engine;
  late ManualTimers timers;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start({
    Question question = _text,
    int? poker,
    JeopardyBoard? board,
    SnowflakeScoring? snowflake,
    Duration countdown = const Duration(seconds: 5),
    Map<String, String?> players = const {'a1': 'a', 'a2': 'a', 'b1': 'b'},
  }) async {
    timers = ManualTimers();
    engine = QuizEngineBloc(
      questionBank: [question],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      mode: const TeamMode(),
      pokerStartingChips: poker,
      jeopardyBoard: board,
      snowflakeScoring: snowflake,
      answerCountdown: countdown,
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
    if (board == null) {
      await send(const StartRoundEvent('q'));
    }
  }

  GameState game() => engine.state.game;

  Future<void> answer(String player, String text, {int? at}) => send(
    SubmitAnswerEvent(
      ShortAnswer(
        playerId: player,
        questionId: 'q',
        clientTimestampMicros: at ?? timers.nowMicros,
        clockOffsetMicros: 0,
        text: text,
      ),
    ),
  );

  Future<void> advance(Duration duration) async {
    timers.advance(duration);
    await pumpEventQueue();
  }

  String? valid(String team) =>
      (game().teamAnswerOf(team) as ShortAnswer?)?.text;

  test('the last answer of a team counts and is scored once', () async {
    await start(countdown: Duration.zero);
    await answer('a1', 'Berlin');
    await advance(const Duration(seconds: 1));
    await answer('a2', 'Bonn');
    await advance(const Duration(seconds: 1));
    await answer('a1', 'Berlin');
    expect(game().round.answers.keys, ['a1']);
    expect(game().round.replacedAnswers, hasLength(2));
    await answer('b1', 'Bonn');
    expect(game().round.status, RoundStatus.revealed);
    expect(game().teamScores, {'a': 10, 'b': 0});
    expect(game().scores.history.where((e) => e.points != 0), hasLength(1));
    // Scoring uses the instant of the replacement.
    expect(game().round.acceptedElapsedMicros['a1'], 2000000);

    final report = SessionReport.fromGame(game(), title: 'x');
    expect(
      {for (final row in report.answers) row.playerId: row.status},
      {
        'a1': ReportAnswerStatus.correct,
        'a2': ReportAnswerStatus.teamAnswered,
        'b1': ReportAnswerStatus.incorrect,
      },
    );
    final protocol = buildGameProtocol(game(), title: 'x');
    expect(
      protocol.questions.single.answers
          .where((a) => a.answer != null)
          .map((a) => a.player),
      ['a1', 'b1'],
    );
  });

  test('"last" follows the host timestamp, never the arrival', () async {
    await start();
    await advance(const Duration(seconds: 5));
    await answer('a2', 'late', at: 4000000);
    await answer('a1', 'early', at: 3000000);
    expect(valid('a'), 'late');
    // A tie is decided by the player id.
    await answer('a1', 'tie', at: 4000000);
    expect(valid('a'), 'late');
    // Repeated frames change nothing.
    await answer('a2', 'late', at: 4000000);
    expect(game().round.allSubmissions, hasLength(3));
  });

  test('a countdown lets teams replace and starts again', () async {
    await start();
    await answer('a1', 'Bonn');
    expect(game().round.answerDeadlineMicros, isNull);
    await answer('b1', 'Berlin');
    expect(game().round.status, RoundStatus.acceptingAnswers);
    expect(game().allAnswersRevision, 1);
    await advance(const Duration(seconds: 4));
    await answer('a2', 'Berlin');
    expect(game().allAnswersRevision, 1, reason: 'announced once');
    await advance(const Duration(seconds: 4));
    expect(game().round.status, RoundStatus.acceptingAnswers);
    await advance(const Duration(seconds: 1));
    expect(game().round.status, RoundStatus.revealed);
    expect(game().teamScores, {'a': 10, 'b': 10});
    await answer('a1', 'Bonn');
    expect(valid('a'), 'Berlin', reason: 'closed rounds stay closed');
  });

  test(
    'the countdown never outlasts the time limit and can be skipped',
    () async {
      await start();
      await advance(const Duration(seconds: 27));
      await answer('a1', 'Bonn');
      await answer('b1', 'Berlin');
      expect(game().round.answerDeadlineMicros, 30000000);
      await send(const EndAnswerCountdownEvent());
      expect(game().round.status, RoundStatus.revealed);
    },
  );

  test(
    'a removed team ends neither the round nor keeps the countdown',
    () async {
      await start();
      await answer('a1', 'Bonn');
      await answer('b1', 'Berlin');
      await send(const PlayerJoinedEvent(Player(id: 'c1', name: 'c1')));
      expect(game().round.answerDeadlineMicros, isNull);
      await advance(const Duration(seconds: 6));
      expect(game().round.status, RoundStatus.acceptingAnswers);
    },
  );

  test('players without a team and solo games end as before', () async {
    await start(players: const {'x': null, 'y': null});
    await answer('x', 'Berlin');
    await answer('x', 'Bonn');
    expect((game().round.answers['x']! as ShortAnswer).text, 'Berlin');
    await answer('y', 'Berlin');
    expect(game().round.status, RoundStatus.revealed);
  });

  test('a judged answer is final', () async {
    await start(
      question: const ShortAnswerQuestion(
        id: 'q',
        prompt: 'Q',
        acceptedAnswers: ['x'],
        manualGrading: true,
        timeLimit: Duration.zero,
      ),
    );
    await answer('a1', 'one');
    await send(
      JudgeAnswerEvent(
        playerId: 'a1',
        questionId: 'q',
        startedAtHostMicros: game().round.startedAtHostMicros!,
        wasCorrect: true,
      ),
    );
    await advance(const Duration(seconds: 1));
    await answer('a2', 'two');
    expect(valid('a'), 'one');
    expect(playerAnswersOf(game(), 'a2').isFinal, isTrue);
  });

  test('poker settles a team once with its valid answer', () async {
    await start(poker: 100);
    for (final id in ['a1', 'b1']) {
      await send(
        PlacePokerWagerEvent(playerId: id, questionId: 'q', wager: 30),
      );
    }
    await send(const OpenPokerAnswersEvent());
    await answer('a1', 'Bonn');
    await advance(const Duration(seconds: 1));
    await answer('a2', 'Berlin');
    await answer('b1', 'Berlin');
    await advance(const Duration(seconds: 1));
    await answer('b1', 'Bonn');
    await advance(const Duration(seconds: 5));
    expect(game().poker!.chips, {'a': 130, 'b': 70});
  });

  test('on a board only the team on turn may replace', () async {
    await start(
      board: const JeopardyBoard(
        rowPoints: [100],
        categories: [
          JeopardyCategory(
            name: 'C',
            cells: [JeopardyCell(questionId: 'q')],
          ),
        ],
      ),
    );
    await send(const StartGameEvent());
    await send(const SelectJeopardyCellEvent('q'));
    final onTurn = game().jeopardy!.currentTeamId!;
    expect(onTurn, 'a');
    await answer('a1', 'Bonn');
    await answer('b1', 'Berlin');
    expect(valid('b'), isNull);
    await advance(const Duration(seconds: 1));
    await answer('a2', 'Berlin');
    await advance(const Duration(seconds: 5));
    expect(game().teamScores['a'], 100);
    expect(game().teamScores['b'], 0);
  });

  test('snowflake compares every player, also in teams', () async {
    const question = TrueFalseQuestion(
      id: 'q',
      prompt: 'Q',
      timeLimit: Duration.zero,
    );
    await start(question: question, snowflake: SnowflakeScoring.winnerOnly);
    for (final (id, value) in [('a1', true), ('a2', false)]) {
      await send(
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: id,
            questionId: 'q',
            clientTimestampMicros: timers.nowMicros,
            clockOffsetMicros: 0,
            value: value,
          ),
        ),
      );
    }
    expect(game().round.answers, hasLength(2));
  });

  test('team changes and removals keep exactly one answer per team', () async {
    await start(players: const {'a1': 'a', 'a2': 'a', 'b1': 'b', 'b2': 'b'});
    await answer('a1', 'one');
    await advance(const Duration(seconds: 1));
    await answer('a2', 'two');
    await send(const AssignTeamEvent(playerId: 'a2', teamId: 'b'));
    expect(valid('a'), 'one');
    expect(valid('b'), 'two');
    await send(const KickPlayerEvent('a2'));
    expect(valid('b'), isNull);
    expect(valid('a'), 'one');
  });

  test('guests learn no answers; a player learns those of the team', () async {
    await start();
    await answer('a1', 'Bonn');
    await advance(const Duration(seconds: 1));
    await answer('a2', 'Geheim');
    final guest = guestSnapshotOf(game(), title: 'x');
    expect(guest.round.answers, isEmpty);
    expect(guest.round.replacedAnswers, isEmpty);
    expect(guest.round.answerCount, 1);
    expect('${guest.toJson()}', isNot(contains('Geheim')));

    final mate = playerAnswersOf(game(), 'a1');
    expect((mate.own! as ShortAnswer).text, 'Bonn');
    expect((mate.valid! as ShortAnswer).text, 'Geheim');
    expect(mate.team, hasLength(2));
    final other = playerAnswersOf(game(), 'b1');
    expect(other, const PlayerAnswers());

    final message = GameSnapshotMessage(guest, answers: mate);
    expect(ServerMessage.decode(message.encode()), message);
  });

  test('a saved round restores replaced answers', () async {
    await start();
    await answer('a1', 'Bonn');
    await advance(const Duration(seconds: 1));
    await answer('a2', 'Berlin');
    final round = RoundState.fromJson(game().round.toJson());
    expect(round, game().round);
  });
}
