/// Verbal answer mode: players answer aloud and the host judges every
/// participant, also those who typed nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const mc = MultipleChoiceQuestion(
  id: 'mc',
  prompt: 'Pick b',
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  correctOptionId: 'b',
);
const text = ShortAnswerQuestion(
  id: 'text',
  prompt: 'Capital?',
  acceptedAnswers: ['Berlin'],
);
const buzz = BuzzerQuestion(id: 'buzz', prompt: 'Buzz', expectedAnswer: 'X');

const teams = {
  'red': Team(id: 'red', name: 'Red'),
  'blue': Team(id: 'blue', name: 'Blue'),
};

void main() {
  late QuizEngineBloc engine;
  var now = 1000000;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  GameState game() => engine.state.game;

  Future<void> join({bool board = false, SnowflakeScoring? snowflake}) async {
    now = 1000000;
    engine = QuizEngineBloc(
      questionBank: const [mc, text, buzz],
      teams: teams,
      mode: board ? const TeamMode() : const SoloMode(),
      snowflakeScoring: snowflake,
      jeopardyBoard: board
          ? const JeopardyBoard(
              rowPoints: [100, 200],
              allowSteal: true,
              categories: [
                JeopardyCategory(
                  name: 'C',
                  cells: [
                    JeopardyCell(questionId: 'mc'),
                    JeopardyCell(questionId: 'text'),
                  ],
                ),
              ],
            )
          : null,
      now: () => now,
    );
    addTearDown(engine.close);
    await send(const StartGameEvent());
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada', teamId: 'red')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Linus', teamId: 'blue')),
    );
  }

  JudgeAnswerEvent judge(String playerId, bool correct) => JudgeAnswerEvent(
    playerId: playerId,
    questionId: game().round.question!.id,
    startedAtHostMicros: game().round.startedAtHostMicros!,
    wasCorrect: correct,
  );

  Future<void> choose(String playerId, String option) => send(
    SubmitAnswerEvent(
      MultipleChoiceAnswer(
        playerId: playerId,
        questionId: game().round.question!.id,
        clientTimestampMicros: now,
        clockOffsetMicros: 0,
        optionId: option,
      ),
    ),
  );

  test('a verbal round is judged by the host, typed or not', () async {
    await join();
    await send(const SetVerbalAnswersEvent(true));
    expect(game().verbalAnswers, isTrue);
    await send(const StartRoundEvent('mc'));
    final round = game().round;
    expect(round.verbal, isTrue);
    expect(round.manualGrading, isTrue);

    now += 2000000;
    // p1 typed the wrong option but said the right thing aloud.
    await choose('p1', 'a');
    expect(game().round.pendingGradeCount, 1);
    await send(const RevealRoundEvent());
    expect(
      game().round.status,
      RoundStatus.locked,
      reason: 'typed answers must be judged before the reveal',
    );

    await send(judge('p1', true));
    // p2 typed nothing and still answered correctly.
    await send(judge('p2', true));
    expect(game().round.answers['p2'], isA<VerbalAnswer>());
    expect(game().round.answerVerdicts, {'p1': 1, 'p2': 1});

    await send(const RevealRoundEvent());
    expect(game().round.status, RoundStatus.revealed);
    expect(game().scores.scoreOf('p1'), greaterThan(0));
    expect(game().scores.scoreOf('p2'), greaterThan(0));
  });

  test('without the mode a missing answer cannot be judged', () async {
    await join();
    await send(const StartRoundEvent('text'));
    expect(game().round.verbal, isFalse);
    await send(judge('p2', true));
    expect(game().round.answers, isEmpty);
    expect(game().round.answerVerdicts, isEmpty);
  });

  test('buzzer rounds stay live and snowflake rejects the mode', () async {
    await join();
    await send(const SetVerbalAnswersEvent(true));
    await send(const StartRoundEvent('buzz'));
    expect(game().round.verbal, isFalse);
    expect(game().round.manualGrading, isFalse);

    await join(snowflake: SnowflakeScoring.winnerOnly);
    await send(const SetVerbalAnswersEvent(true));
    expect(game().verbalAnswers, isFalse);
  });

  test('switching mid-round only applies while nothing was judged', () async {
    await join();
    await send(const StartRoundEvent('text'));
    await send(const SetVerbalAnswersEvent(true));
    expect(game().round.verbal, isTrue, reason: 'nothing judged yet');
    await send(judge('p2', false));
    await send(const SetVerbalAnswersEvent(false));
    expect(game().verbalAnswers, isFalse);
    expect(
      game().round.verbal,
      isTrue,
      reason: 'a judged round keeps its rules until it ends',
    );
  });

  test('undoing a verbal verdict removes the spoken answer', () async {
    await join();
    await send(const SetVerbalAnswersEvent(true));
    await send(const StartRoundEvent('text'));
    await send(judge('p2', true));
    final correction = game().corrections.single;
    await send(UndoCorrectionEvent(correction.id));
    expect(game().round.answers.containsKey('p2'), isFalse);
    expect(game().round.answerVerdicts, isEmpty);
    expect(game().round.pendingGradeCount, 0);
  });

  test('on a board only the team on turn can be judged', () async {
    await join(board: true);
    await send(const SetVerbalAnswersEvent(true));
    final turn = game().jeopardy!.currentTeamId!;
    final onTurn = turn == 'red' ? 'p1' : 'p2';
    final other = onTurn == 'p1' ? 'p2' : 'p1';
    await send(const SelectJeopardyCellEvent('text'));
    expect(game().round.verbal, isTrue);
    expect(game().mayJudgeVerbally(onTurn), isTrue);
    expect(game().mayJudgeVerbally(other), isFalse);
    await send(judge(other, true));
    expect(game().round.answers.containsKey(other), isFalse);
    await send(judge(onTurn, true));
    expect(game().round.answers[onTurn], isA<VerbalAnswer>());
  });

  test('state with verbal answers survives serialization', () async {
    await join();
    await send(const SetVerbalAnswersEvent(true));
    await send(const StartRoundEvent('mc'));
    await send(judge('p2', true));
    final restored = GameState.fromJson(game().toJson());
    expect(restored, game());
    expect(restored.round.answers['p2'], isA<VerbalAnswer>());
    // Older saves without the fields stay readable.
    final legacy = game().toJson()
      ..remove('verbalAnswers')
      ..['round'] = ({...game().round.toJson()}
        ..remove('verbal')
        ..['answers'] = <String, Object?>{}
        ..['answerVerdicts'] = <String, Object?>{}
        ..['acceptedElapsedMicros'] = <String, Object?>{});
    expect(GameState.fromJson(legacy).verbalAnswers, isFalse);
    expect(GameState.fromJson(legacy).round.verbal, isFalse);
  });

  group('on-turn answers', () {
    test('show the picking team pick, never the others or a steal', () async {
      await join(board: true);
      final turn = game().jeopardy!.currentTeamId!;
      final onTurn = turn == 'red' ? 'p1' : 'p2';
      await send(const SelectJeopardyCellEvent('mc'));
      expect(game().onTurnAnswers, isEmpty);
      // The only member of the picking team answered: the round closes.
      await choose(onTurn, 'a');
      expect(
        game().jeopardy!.isStealRound,
        isTrue,
        reason: 'a miss passes the question to the others',
      );
      expect(game().onTurnAnswers, isEmpty);
      await choose(onTurn == 'p1' ? 'p2' : 'p1', 'b');
      await send(const CloseRoundEvent());

      final next = game().jeopardy!.currentTeamId!;
      final picker = next == 'red' ? 'p1' : 'p2';
      // Judged rounds stay open after the answer, so the TV can show it.
      await send(const SetVerbalAnswersEvent(true));
      await send(const SelectJeopardyCellEvent('text'));
      await send(
        SubmitAnswerEvent(
          ShortAnswer(
            playerId: picker,
            questionId: 'text',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
            text: 'Berlin',
          ),
        ),
      );
      expect(game().onTurnAnswers.single.playerId, picker);
      expect(
        game().redactedForPlayers().onTurnAnswers,
        isEmpty,
        reason: 'the team may still replace its answer',
      );
      expect(game().redactedForPlayers().round.answerCount, 1);
      await send(judge(picker, true));
      await send(const RevealRoundEvent());
      expect(game().round.status, RoundStatus.revealed);
      expect(game().onTurnAnswers, isEmpty);
    });

    test('are empty when everybody answers at once', () async {
      await join();
      await send(const StartRoundEvent('mc'));
      await choose('p1', 'a');
      expect(game().onTurnAnswers, isEmpty);
    });
  });
}
