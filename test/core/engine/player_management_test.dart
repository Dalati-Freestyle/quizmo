import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  const question = TrueFalseQuestion(
    id: 'q',
    prompt: '?',
    correctAnswer: true,
    scoringRule: FixedPointsRule(correctPoints: 10),
  );
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: const [question],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'old', name: 'Ada', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'new', name: 'Ada', teamId: 'b')),
    );
  });
  tearDown(() => engine.close());
  Future<void> scoreBoth() async {
    await send(const StartRoundEvent('q'));
    for (final id in ['old', 'new']) {
      await send(
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: id,
            questionId: 'q',
            clientTimestampMicros: engine.hostNowMicros,
            clockOffsetMicros: 0,
            value: true,
          ),
        ),
      );
    }
  }

  test(
    'merge requires disconnected source and connected target and sums history',
    () async {
      await scoreBoth();
      const merge = MergePlayersEvent(
        sourcePlayerId: 'old',
        targetPlayerId: 'new',
      );
      await send(merge);
      expect(engine.state.game.players, hasLength(2));
      await send(const PlayerLeftEvent('new'));
      await send(const PlayerLeftEvent('old'));
      await send(merge);
      expect(engine.state.game.players, hasLength(2));
      await send(const PlayerJoinedEvent(Player(id: 'new', name: 'Ada')));
      await send(merge);
      final game = engine.state.game;
      expect(game.players.keys, ['new']);
      expect(game.players['new']!.teamId, 'b');
      expect(game.scores.scoreOf('new'), 20);
      expect(game.scores.history.map((e) => e.playerId), everyElement('new'));
      expect(game.teamScores['b'], 20);
      expect(game.round.answers.keys, ['new']);
      await send(merge);
      expect(engine.state.game.scores.scoreOf('new'), 20);
    },
  );
  test('kick removes player, score and active submissions', () async {
    await send(const StartRoundEvent('q'));
    await send(
      SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'old',
          questionId: 'q',
          clientTimestampMicros: engine.hostNowMicros,
          clockOffsetMicros: 0,
          value: true,
        ),
      ),
    );
    await send(const KickPlayerEvent('old'));
    expect(engine.state.game.players.containsKey('old'), isFalse);
    expect(engine.state.game.round.answers, isEmpty);
    expect(engine.state.game.scores.byPlayer.containsKey('old'), isFalse);
    await send(const EndRoundEvent());
    expect(engine.state.game.scores.history, isEmpty);
  });
  test('all answered emits one revision and quiz completion resets', () async {
    await scoreBoth();
    expect(engine.state.game.allAnswersRevision, 1);
    expect(engine.state.game.isFinished, isTrue);
    expect(engine.state.game.redactedForPlayers().isFinished, isTrue);
    await send(const RevealRoundEvent());
    expect(engine.state.game.allAnswersRevision, 1);
    await send(const ResetGameEvent());
    expect(engine.state.game.isFinished, isFalse);
  });
  test('merging a disconnected buzzer winner preserves the floor and adjusted timestamp', () async {
    await engine.close();
    engine = QuizEngineBloc(
      questionBank: const [BuzzerQuestion(id: 'q', prompt: '?')],
      buzzerGraceWindow: const Duration(days: 1),
    );
    await send(const PlayerJoinedEvent(Player(id: 'old', name: 'Ada')));
    await send(const PlayerJoinedEvent(Player(id: 'new', name: 'Ada')));
    await send(const StartRoundEvent('q'));
    const press = BuzzerPress(
      playerId: 'old',
      questionId: 'q',
      clientTimestampMicros: 100,
      clockOffsetMicros: 30,
    );
    await send(const BuzzerPressEvent(press));
    await send(const LockBuzzerEvent());
    await send(const PlayerLeftEvent('old'));
    await send(
      const MergePlayersEvent(sourcePlayerId: 'old', targetPlayerId: 'new'),
    );
    expect(engine.state.game.round.activePlayerId, 'new');
    expect(engine.state.roundStatus, RoundStatus.locked);
    expect(engine.state.game.round.buzzerQueue.single.hostTimestampMicros, 70);
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    expect(engine.state.game.scores.scoreOf('new'), greaterThan(0));
  });
}
