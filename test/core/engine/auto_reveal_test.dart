/// Every automatically scored question kind closes and reveals by itself once
/// all teams (or players) answered, like free text (issue #70).
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

import '../../support/manual_timers.dart';

const _limit = Duration(seconds: 30);

final _cases = <(Question, AnswerSubmission Function(String player))>[
  (
    const MultipleChoiceQuestion(
      id: 'q',
      prompt: '?',
      timeLimit: _limit,
      options: [
        AnswerOption(id: 'x', label: 'X'),
        AnswerOption(id: 'y', label: 'Y'),
      ],
      correctOptionIds: ['x'],
    ),
    (p) => MultipleChoiceAnswer(
      playerId: p,
      questionId: 'q',
      clientTimestampMicros: 0,
      clockOffsetMicros: 0,
      optionId: 'x',
    ),
  ),
  (
    const TrueFalseQuestion(
      id: 'q',
      prompt: '?',
      correctAnswer: true,
      timeLimit: _limit,
    ),
    (p) => TrueFalseAnswer(
      playerId: p,
      questionId: 'q',
      clientTimestampMicros: 0,
      clockOffsetMicros: 0,
      value: true,
    ),
  ),
  (
    const ShortAnswerQuestion(
      id: 'q',
      prompt: '?',
      acceptedAnswers: ['a'],
      timeLimit: _limit,
    ),
    (p) => ShortAnswer(
      playerId: p,
      questionId: 'q',
      clientTimestampMicros: 0,
      clockOffsetMicros: 0,
      text: 'a',
    ),
  ),
];

void main() {
  late QuizEngineBloc engine;
  late ManualTimers timers;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start(
    Question question, {
    required bool teams,
    bool soft = false,
  }) async {
    timers = ManualTimers();
    engine = QuizEngineBloc(
      questionBank: [
        soft
            ? Question.fromJson({...question.toJson(), 'softTimeLimit': true})
            : question,
      ],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      mode: teams ? const TeamMode() : const SoloMode(),
      answerCountdown: const Duration(seconds: 5),
      now: () => timers.nowMicros,
      createTimer: timers.create,
    );
    addTearDown(engine.close);
    for (final (id, team) in [('a1', 'a'), ('a2', 'a'), ('b1', 'b')]) {
      await send(PlayerJoinedEvent(Player(id: id, name: id, teamId: team)));
    }
    await send(StartRoundEvent(question.id));
  }

  for (final (question, answer) in _cases) {
    final kind = question.runtimeType;
    test('$kind: a team game counts down and reveals', () async {
      await start(question, teams: true);
      await send(SubmitAnswerEvent(answer('a1')));
      expect(engine.state.game.round.answerDeadlineMicros, isNull);
      await send(SubmitAnswerEvent(answer('b1')));
      expect(engine.state.game.round.answerDeadlineMicros, isNotNull);
      timers.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(engine.state.game.round.status, RoundStatus.revealed);
    });

    test('$kind: also with a soft time limit', () async {
      await start(question, teams: true, soft: true);
      expect(engine.state.game.round.hasSoftTimer, isTrue);
      await send(SubmitAnswerEvent(answer('a1')));
      await send(SubmitAnswerEvent(answer('b1')));
      expect(engine.state.game.round.answerDeadlineMicros, isNotNull);
      timers.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(
        engine.state.game.round.status,
        isNot(RoundStatus.acceptingAnswers),
      );
    });

    test('$kind: a solo game reveals once everybody answered', () async {
      await start(question, teams: false);
      for (final player in ['a1', 'a2', 'b1']) {
        await send(SubmitAnswerEvent(answer(player)));
      }
      timers.advance(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(engine.state.game.round.status, RoundStatus.revealed);
    });
  }
}
