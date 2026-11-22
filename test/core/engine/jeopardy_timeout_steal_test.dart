/// Stealing on a Jeopardy board after the clock of the picking team ran out.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const int kEpoch = 1700000000000000;

const choice = MultipleChoiceQuestion(
  id: 'q-mc',
  prompt: 'Pick b',
  timeLimit: Duration(seconds: 10),
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  correctOptionId: 'b',
);

const buzzer = BuzzerQuestion(
  id: 'q-buzz',
  prompt: 'Buzz',
  timeLimit: Duration(seconds: 10),
  expectedAnswer: 'Gold',
);

const teams = {
  'red': Team(id: 'red', name: 'Red'),
  'blue': Team(id: 'blue', name: 'Blue'),
};

final board = JeopardyBoard(
  rowPoints: const [100, 200],
  allowSteal: true,
  categories: const [
    JeopardyCategory(
      name: 'Mixed',
      cells: [
        JeopardyCell(questionId: 'q-mc'),
        JeopardyCell(questionId: 'q-buzz'),
      ],
    ),
  ],
);

class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  bool active = true;
  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
}

void main() {
  late QuizEngineBloc engine;
  late int now;
  final timers = <_FakeTimer>[];

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  /// Fires every running round timer, i.e. the clock runs out.
  Future<void> expire() async {
    now += const Duration(seconds: 11).inMicroseconds;
    for (final timer in [...timers]) {
      if (timer.active) {
        timer.active = false;
        timer.callback();
      }
    }
    await pumpEventQueue();
  }

  GameState game() => engine.state.game;

  setUp(() async {
    now = kEpoch;
    timers.clear();
    engine = QuizEngineBloc(
      questionBank: const [choice, buzzer],
      teams: teams,
      mode: const TeamMode(),
      jeopardyBoard: board,
      autoContinueBuzzer: false,
      now: () => now,
      createTimer: (duration, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    await send(const StartGameEvent());
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'Ada', teamId: 'red')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Linus', teamId: 'blue')),
    );
  });
  tearDown(() => engine.close());

  Future<void> stealSucceeds(
    String questionId,
    Future<void> Function() win,
  ) async {
    expect(game().jeopardy!.isStealRound, isTrue, reason: 'steal round open');
    expect(game().round.status, RoundStatus.acceptingAnswers);
    expect(game().round.question?.id, questionId);
    expect(
      timers.where((timer) => timer.active),
      isNotEmpty,
      reason: 'the steal round has its own clock',
    );
    await win();
    expect(game().scores.byPlayer['p2'], greaterThan(0));
  }

  test(
    'multiple choice: timeout of the picking team opens the steal',
    () async {
      await send(const SelectJeopardyCellEvent('q-mc'));
      expect(game().jeopardy!.isStealRound, isFalse);
      await expire();
      await stealSucceeds('q-mc', () async {
        await send(
          SubmitAnswerEvent(
            MultipleChoiceAnswer(
              playerId: 'p2',
              questionId: 'q-mc',
              clientTimestampMicros: now,
              clockOffsetMicros: 0,
              optionId: 'b',
            ),
          ),
        );
        if (game().round.status != RoundStatus.revealed) {
          await send(const RevealRoundEvent());
        }
      });
    },
  );

  test('buzzer: timeout without a press opens the steal', () async {
    await send(const SelectJeopardyCellEvent('q-buzz'));
    await expire();
    if (!game().jeopardy!.isStealRound) await send(const RevealRoundEvent());
    await stealSucceeds('q-buzz', () async {
      await send(
        BuzzerPressEvent(
          BuzzerPress(
            playerId: 'p2',
            questionId: 'q-buzz',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
          ),
        ),
      );
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: true));
    });
  });

  test('the steal round can time out too and then reveals', () async {
    await send(const SelectJeopardyCellEvent('q-mc'));
    await expire();
    expect(game().jeopardy!.isStealRound, isTrue);
    await expire();
    await send(const RevealRoundEvent());
    expect(game().round.status, RoundStatus.revealed);
  });
}
