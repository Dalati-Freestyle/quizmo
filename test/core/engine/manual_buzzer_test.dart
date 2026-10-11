import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  test(
    'host reopens after a miss, discards old queue and keeps loser locked out',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [BuzzerQuestion(id: 'q', prompt: '?')],
        autoContinueBuzzer: false,
        buzzerGraceWindow: const Duration(days: 1),
      );
      addTearDown(engine.close);
      Future<void> send(QuizEngineEvent event) async {
        engine.add(event);
        await pumpEventQueue();
      }

      Future<void> buzz(String id) => send(
        BuzzerPressEvent(
          BuzzerPress(
            playerId: id,
            questionId: 'q',
            clientTimestampMicros: engine.hostNowMicros,
            clockOffsetMicros: 0,
          ),
        ),
      );
      for (final id in ['a', 'b', 'c']) {
        await send(PlayerJoinedEvent(Player(id: id, name: id)));
      }
      await send(const StartRoundEvent('q'));
      await buzz('a');
      await buzz('b');
      await send(const LockBuzzerEvent());
      await send(const ReopenBuzzerEvent());
      expect(engine.state.game.round.activePlayerId, 'a');
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(engine.state.roundStatus, RoundStatus.locked);
      expect(engine.state.game.round.activePlayerId, isNull);
      await buzz('c');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await send(const ReopenBuzzerEvent());
      expect(engine.state.roundStatus, RoundStatus.acceptingAnswers);
      await buzz('a');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await buzz('b');
      expect(engine.state.game.round.buzzerQueue.single.playerId, 'b');
      await send(const ReopenBuzzerEvent(forAll: true));
      expect(engine.state.game.round.lockedOutPlayerIds, isEmpty);
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      expect(engine.state.game.round.resolvedAttempts, 1);
      await buzz('a');
      expect(engine.state.game.round.buzzerQueue.single.playerId, 'a');
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      await send(const ReopenBuzzerEvent());
      await buzz('a');
      expect(engine.state.game.round.buzzerQueue, isEmpty);
      await buzz('c');
      expect(engine.state.game.round.buzzerQueue.single.playerId, 'c');
      await send(const EndRoundEvent());
      expect(engine.state.roundStatus, RoundStatus.revealed);
    },
  );
  test('host can end a Jeopardy question without opening a steal', () async {
    final engine = QuizEngineBloc(
      questionBank: const [BuzzerQuestion(id: 'q', prompt: '?')],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      jeopardyBoard: const JeopardyBoard(
        rowPoints: [100],
        allowSteal: true,
        categories: [
          JeopardyCategory(
            name: 'C',
            cells: [JeopardyCell(questionId: 'q')],
          ),
        ],
      ),
      autoContinueBuzzer: false,
    );
    addTearDown(engine.close);
    engine.add(const SelectJeopardyCellEvent('q'));
    await pumpEventQueue();
    engine.add(const EndRoundEvent());
    await pumpEventQueue();
    expect(engine.state.roundStatus, RoundStatus.revealed);
    expect(engine.state.game.jeopardy!.isStealRound, isFalse);
    expect(engine.state.game.isFinished, isTrue);
  });
}
