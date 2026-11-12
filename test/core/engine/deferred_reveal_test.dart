import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const questions = [
  TrueFalseQuestion(id: 'q1', prompt: 'First?', correctAnswer: true),
  ShortAnswerQuestion(
    id: 'q2',
    prompt: 'Second?',
    acceptedAnswers: ['Berlin'],
    manualGrading: true,
    solutionMedia: [CodeAttachment(code: 'secret solution', language: 'text')],
    adminNotes: 'private host note',
  ),
];

void main() {
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: questions,
      revealMode: SolutionRevealMode.atEnd,
      now: () => 1000000,
    );
    await send(const PlayerJoinedEvent(Player(id: 'p', name: 'Player')));
    await send(const StartRoundEvent('q1'));
  });
  tearDown(() => engine.close());

  Future<void> firstAnswer() => send(
    const SubmitAnswerEvent(
      TrueFalseAnswer(
        playerId: 'p',
        questionId: 'q1',
        clientTimestampMicros: 1100000,
        clockOffsetMicros: 0,
        value: true,
      ),
    ),
  );

  test('host sees results while every public surface remains hidden', () async {
    await firstAnswer();
    final host = engine.state.game;
    expect(host.round.status, RoundStatus.revealed);
    expect(host.scores.scoreOf('p'), 10);
    expect(host.roundHistory, hasLength(1));
    final public = GameState.fromJson(host.redactedForPlayers().toJson());
    expect(public.resultsHidden, isTrue);
    expect(public.round.status, RoundStatus.locked);
    expect(public.round.question!.hasSolution, isFalse);
    expect(public.scores, const ScoreState());
    expect(public.questionWinners, isEmpty);
    expect(public.roundHistory, isEmpty);
    expect(public.round.answerVerdicts, isEmpty);
    expect(public.round.buzzerVerdicts, isEmpty);
    expect(public.showFinalReview, isFalse);

    await send(const NextQuestionEvent());
    expect(engine.state.game.round.question!.id, 'q2');
    expect(engine.state.game.redactedForPlayers().scores.history, isEmpty);
  });

  test(
    'final reveal publishes all solutions, decisions and accumulated scores',
    () async {
      await firstAnswer();
      await send(const NextQuestionEvent());
      await send(
        const SubmitAnswerEvent(
          ShortAnswer(
            playerId: 'p',
            questionId: 'q2',
            clientTimestampMicros: 1200000,
            clockOffsetMicros: 0,
            text: 'Hamburg',
          ),
        ),
      );
      await send(const RevealRoundEvent());
      expect(engine.state.game.isFinished, isFalse);
      await send(
        const JudgeAnswerEvent(
          playerId: 'p',
          questionId: 'q2',
          startedAtHostMicros: 1000000,
          wasCorrect: true,
        ),
      );
      expect(
        engine.state.game.redactedForPlayers().round.answerVerdicts,
        isEmpty,
      );
      await send(const RevealRoundEvent());
      final public = GameState.fromJson(
        engine.state.game.redactedForPlayers().toJson(),
      );
      expect(public.resultsHidden, isFalse);
      expect(public.showFinalReview, isTrue);
      expect(public.scores.scoreOf('p'), 20);
      expect(public.roundHistory.map((r) => r.question!.id), ['q1', 'q2']);
      expect(public.roundHistory.every((r) => r.question!.hasSolution), isTrue);
      expect(public.roundHistory.last.answerVerdicts, {'p': 1});
      expect(public.roundHistory.last.question!.solutionMedia, hasLength(1));
      expect(jsonEncode(public.toJson()), isNot(contains('private host note')));

      await send(const RevealRoundEvent());
      expect(engine.state.game.roundHistory, hasLength(2));
      await send(const CloseRoundEvent());
      expect(engine.state.game.redactedForPlayers().showFinalReview, isTrue);
    },
  );

  test(
    'reset clears review and restores hidden standings without losing mode',
    () async {
      await firstAnswer();
      await send(const ResetGameEvent());
      final game = engine.state.game;
      expect(game.revealMode, SolutionRevealMode.atEnd);
      expect(game.roundHistory, isEmpty);
      expect(game.resultsHidden, isTrue);
      expect(game.isFinished, isFalse);
      expect(game.completedQuestionIds, isEmpty);
      expect(game.scores.scoreOf('p'), 0);
    },
  );

  test(
    'default mode still reveals every round without an end review',
    () async {
      await engine.close();
      engine = QuizEngineBloc(questionBank: questions, now: () => 1000000);
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'Player')));
      await send(const StartRoundEvent('q1'));
      await firstAnswer();
      final public = engine.state.game.redactedForPlayers();
      expect(public.resultsHidden, isFalse);
      expect(public.round.status, RoundStatus.revealed);
      expect(public.round.question!.hasSolution, isTrue);
      expect(public.scores.scoreOf('p'), 10);
      expect(public.roundHistory, isEmpty);
    },
  );

  test('deferred mode is restricted to standard quizzes', () {
    expect(
      () => QuizEngineBloc(
        revealMode: SolutionRevealMode.atEnd,
        pokerStartingChips: 100,
      ),
      throwsArgumentError,
    );
  });

  test(
    'buzzer scores and host verdicts are hidden before the final question',
    () async {
      await engine.close();
      engine = QuizEngineBloc(
        revealMode: SolutionRevealMode.atEnd,
        questionBank: const [
          BuzzerQuestion(
            id: 'buzz',
            prompt: 'Name it.',
            expectedAnswer: 'Gold',
          ),
          TrueFalseQuestion(id: 'last', prompt: 'Last?', correctAnswer: true),
        ],
        now: () => 1000000,
      );
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'Player')));
      await send(const StartRoundEvent('buzz'));
      await send(
        const BuzzerPressEvent(
          BuzzerPress(
            playerId: 'p',
            questionId: 'buzz',
            clientTimestampMicros: 1100000,
            clockOffsetMicros: 0,
          ),
        ),
      );
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      expect(engine.state.game.scores.scoreOf('p'), greaterThan(0));
      final public = engine.state.game.redactedForPlayers();
      expect(public.scores, const ScoreState());
      expect(public.round.buzzerVerdicts, isEmpty);
      expect(public.round.buzzerAnswerCorrect, isFalse);
      expect(public.round.question!.hasSolution, isFalse);
      expect(public.roundHistory, isEmpty);
    },
  );
}
