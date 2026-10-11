import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const bank = [
  TrueFalseQuestion(id: 'q1', prompt: 'First', correctAnswer: true),
  TrueFalseQuestion(id: 'q2', prompt: 'Second', correctAnswer: true),
];
const board = JeopardyBoard(
  rowPoints: [100, 200],
  allowSteal: false,
  categories: [
    JeopardyCategory(
      name: 'Category',
      cells: [
        JeopardyCell(questionId: 'q1'),
        JeopardyCell(questionId: 'q2'),
      ],
    ),
  ],
);

void main() {
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    if (event is SelectJeopardyCellEvent && !engine.state.game.isStarted) {
      engine.add(const StartGameEvent());
      await pumpEventQueue();
    }
    engine.add(event);
    await pumpEventQueue();
  }

  setUp(
    () => engine = QuizEngineBloc(
      questionBank: bank,
      jeopardyBoard: board,
      now: () => 1000000,
    ),
  );
  tearDown(() => engine.close());

  test('solo turns follow joins, survive reconnects and restrict picks and answers', () async {
    await send(const PlayerJoinedEvent(Player(id: 'b', name: 'B')));
    await send(const PlayerJoinedEvent(Player(id: 'a', name: 'A')));
    await send(const PlayerLeftEvent('b'));
    await send(const PlayerJoinedEvent(Player(id: 'b', name: 'B')));
    expect(engine.state.game.selectionOrder, ['b', 'a']);
    expect(engine.state.game.jeopardy!.currentTeamId, 'b');
    await send(const SelectJeopardyCellEvent('q1', playerId: 'a'));
    expect(engine.state.game.jeopardy!.pendingPickQuestionId, isNull);
    await send(const SelectJeopardyCellEvent('q1', playerId: 'b'));
    expect(engine.state.game.round.question, isNull);
    expect(engine.state.game.jeopardy!.pendingPickQuestionId, 'q1');
    await send(const SelectJeopardyCellEvent('q2'));
    await send(const SetJeopardyTurnEvent('a'));
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q2',
        playerId: 'b',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question, isNull);
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q1',
        playerId: 'b',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question!.id, 'q1');
    await send(
      const SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'a',
          questionId: 'q1',
          clientTimestampMicros: 1000001,
          clockOffsetMicros: 0,
          value: true,
        ),
      ),
    );
    expect(engine.state.game.round.answers, isEmpty);
    await send(
      const SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'b',
          questionId: 'q1',
          clientTimestampMicros: 1000002,
          clockOffsetMicros: 0,
          value: true,
        ),
      ),
    );
    expect(engine.state.game.round.status, RoundStatus.revealed);
    expect(engine.state.game.jeopardy!.currentTeamId, 'a');
    expect(engine.state.game.scores.scoreOf('b'), 100);
  });

  test(
    'host order is validated, sets the first turn and survives reset and JSON',
    () async {
      await send(const PlayerJoinedEvent(Player(id: 'b', name: 'B')));
      await send(const PlayerJoinedEvent(Player(id: 'a', name: 'A')));
      await send(const SetPlayerOrderEvent(['a', 'b']));
      await send(const SetPlayerOrderEvent(['a', 'a']));
      expect(engine.state.game.orderedPlayerIds, ['a', 'b']);
      expect(engine.state.game.jeopardy!.currentTeamId, 'a');
      expect(GameState.fromJson(engine.state.game.toJson()).selectionOrder, [
        'a',
        'b',
      ]);
      await send(const ResetGameEvent());
      expect(engine.state.game.selectionOrder, ['a', 'b']);
      expect(engine.state.game.jeopardy!.currentTeamId, 'a');
      await send(const PlayerJoinedEvent(Player(id: 'c', name: 'C')));
      expect(engine.state.game.selectionOrder, ['a', 'b', 'c']);
    },
  );

  test('rejecting a choice leaves the board available and stale approval does nothing', () async {
    await send(const PlayerJoinedEvent(Player(id: 'a', name: 'A')));
    await send(const SelectJeopardyCellEvent('q1', playerId: 'a'));
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q1',
        playerId: 'a',
        accepted: false,
      ),
    );
    expect(engine.state.game.jeopardy!.pendingPickQuestionId, isNull);
    expect(engine.state.game.completedQuestionIds, isEmpty);
    await send(const SelectJeopardyCellEvent('q2', playerId: 'a'));
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q1',
        playerId: 'a',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question, isNull);
    await send(const ResetGameEvent());
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q2',
        playerId: 'a',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question, isNull);
  });

  test('team order follows first joining member and every member of current team may pick', () async {
    await engine.close();
    engine = QuizEngineBloc(
      questionBank: bank,
      jeopardyBoard: board,
      mode: const TeamMode(),
      teams: const {
        'red': Team(id: 'red', name: 'Red'),
        'blue': Team(id: 'blue', name: 'Blue'),
      },
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'b', name: 'B', teamId: 'blue')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'r', name: 'R', teamId: 'red')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'b2', name: 'B2', teamId: 'blue')),
    );
    expect(engine.state.game.selectionOrder, ['blue', 'red']);
    await send(const StartGameEvent());
    expect(engine.state.game.mayPickQuestion('r'), isFalse);
    expect(engine.state.game.mayPickQuestion('b2'), isTrue);
    await send(const SelectJeopardyCellEvent('q1', playerId: 'b2'));
    final public = GameState.fromJson(
      engine.state.game.redactedForPlayers().toJson(),
    );
    expect(public.jeopardy!.pendingPickQuestionId, 'q1');
    expect(public.questionBank, isEmpty);
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q1',
        playerId: 'b2',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question!.id, 'q1');
  });

  test('removed chooser cannot be approved', () async {
    await send(const PlayerJoinedEvent(Player(id: 'a', name: 'A')));
    await send(const PlayerJoinedEvent(Player(id: 'b', name: 'B')));
    await send(const SelectJeopardyCellEvent('q1', playerId: 'a'));
    await send(const KickPlayerEvent('a'));
    await send(
      const ConfirmQuestionPickEvent(
        questionId: 'q1',
        playerId: 'a',
        accepted: true,
      ),
    );
    expect(engine.state.game.round.question, isNull);
    expect(engine.state.game.jeopardy!.currentTeamId, 'b');
  });
}
