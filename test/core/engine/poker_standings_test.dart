import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

final _questions = [
  for (var i = 1; i <= 6; i++)
    TrueFalseQuestion(
      id: 'q$i',
      prompt: 'Question $i?',
      correctAnswer: true,
      timeLimit: Duration.zero,
    ),
];

void main() {
  late QuizEngineBloc engine;
  final teams = ['a', 'b', 'c', 'd'];

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: _questions,
      teams: {for (final id in teams) id: Team(id: id, name: 'Team $id')},
      pokerStartingChips: 100,
    );
    for (final id in teams) {
      engine.add(
        PlayerJoinedEvent(Player(id: 'p$id', name: 'P$id', teamId: id)),
      );
    }
    await pumpEventQueue();
  });
  tearDown(() => engine.close());

  GameState game() => engine.state.game;

  Future<void> bet(String question, Map<String, int> stakes) async {
    engine.add(StartRoundEvent(question));
    await pumpEventQueue();
    for (final MapEntry(key: team, value: stake) in stakes.entries) {
      engine.add(
        PlacePokerWagerEvent(
          playerId: 'p$team',
          questionId: question,
          wager: stake,
        ),
      );
    }
    await pumpEventQueue();
  }

  Future<void> play(
    String question,
    Map<String, int> stakes, {
    Set<String> right = const {},
  }) async {
    await bet(question, stakes);
    engine.add(const OpenPokerAnswersEvent());
    await pumpEventQueue();
    for (final team in stakes.keys) {
      engine.add(
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: 'p$team',
            questionId: question,
            clientTimestampMicros: engine.state.game.hostTimeMicros,
            clockOffsetMicros: 0,
            value: right.contains(team),
          ),
        ),
      );
    }
    await pumpEventQueue();
    engine.add(const RevealRoundEvent());
    await pumpEventQueue();
    engine.add(const CloseRoundEvent());
    await pumpEventQueue();
  }

  List<String> order() => [
    for (final (team, place) in rankTeams(game())) '$place${team.id}',
  ];

  var request = 0;
  Future<void> correct(String team, int delta) async {
    engine.add(
      CorrectScoreEvent(
        requestId: 'r${request++}',
        teamId: team,
        delta: delta,
        reason: 'test',
      ),
    );
    await pumpEventQueue();
  }

  test(
    'later eliminations rank ahead, the same question shares a place',
    () async {
      await play('q1', {'b': 100, 'c': 100});
      await play('q2', {'d': 100, 'a': 10}, right: {'a'});
      expect(game().poker!.eliminations, {'b': 1, 'c': 1, 'd': 2});
      expect(order(), ['1a', '2d', '3b', '3c']);

      final protocol = buildGameProtocol(game(), title: 'x');
      expect(
        [for (final s in protocol.standings) (s.id, s.place, s.eliminatedAt)],
        [('a', 1, null), ('d', 2, 2), ('b', 3, 1), ('c', 3, 1)],
      );
      expect(
        GameProtocol.fromJson(protocol.toJson()).standings,
        protocol.standings,
      );
      final report = SessionReport.fromGame(game(), title: 'x');
      expect(
        [
          for (final s in report.summaries)
            if (s.isTeam) s.id,
        ],
        ['a', 'd', 'b', 'c'],
      );
      expect(report.toCsv(), contains('eliminated_at_question'));
    },
  );

  test('an all-in is no elimination while the question runs', () async {
    await bet('q1', {'b': 100});
    expect(game().poker!.chips['b'], 0);
    expect(game().poker!.eliminations, isEmpty);
    expect(order().last, '4b');
    engine.add(const FinishQuizEvent(early: true));
    await pumpEventQueue();
    expect(game().poker!.eliminations, isEmpty);
  });

  test('when everybody is out, the last ones share the win', () async {
    await play('q1', {'b': 100, 'c': 100});
    await play('q2', {'a': 100, 'd': 100});
    expect(order(), ['1a', '1d', '3b', '3c']);
  });

  test('practice answers do not move the moment', () async {
    await play('q1', {'b': 100});
    await bet('q2', {'a': 10});
    engine.add(const OpenPokerAnswersEvent());
    await pumpEventQueue();
    engine.add(
      SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'pb',
          questionId: 'q2',
          clientTimestampMicros: game().hostTimeMicros,
          clockOffsetMicros: 0,
          value: true,
        ),
      ),
    );
    await pumpEventQueue();
    engine.add(const RevealRoundEvent());
    await pumpEventQueue();
    expect(game().poker!.eliminations, {'b': 1});
  });

  test(
    'corrections bring teams back, take them out and can be undone',
    () async {
      await play('q1', {'b': 100});
      await play('q2', {'c': 50});
      await correct('b', 10);
      expect(game().poker!.eliminations, isEmpty);
      engine.add(UndoCorrectionEvent(game().corrections.last.id));
      await pumpEventQueue();
      expect(game().poker!.eliminations, {'b': 1});

      await correct('c', -50);
      expect(game().poker!.eliminations, {'b': 1, 'c': 2});
      engine.add(UndoCorrectionEvent(game().corrections.last.id));
      await pumpEventQueue();
      expect(game().poker!.eliminations, {'b': 1});

      await correct('b', 20);
      await play('q3', {'b': 20});
      expect(game().poker!.eliminations, {'b': 3});
    },
  );

  test('reset clears the moments, older saves count as first out', () async {
    await play('q1', {'b': 100});
    final json = {...game().poker!.toJson()}..remove('eliminations');
    expect(PokerState.fromJson(json).eliminations, {'b': 0});
    expect(PokerState.fromJson(game().poker!.toJson()), game().poker);
    engine.add(const ResetGameEvent());
    await pumpEventQueue();
    expect(game().poker!.eliminations, isEmpty);
  });
}
