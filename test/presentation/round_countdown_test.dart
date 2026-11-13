import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/round_countdown.dart';

const _start = 1700000000000000;
const _question = BuzzerQuestion(
  id: 'q',
  prompt: 'Buzz',
  timeLimit: Duration(seconds: 20),
);

GameState _game({
  RoundStatus status = RoundStatus.acceptingAnswers,
  int? restartedAt,
  bool betting = false,
  bool paused = false,
  int hostTime = _start,
}) => GameState(
  hostTimeMicros: hostTime,
  recoveryPaused: paused,
  poker: betting
      ? const PokerState(startingChips: 100, chips: {'a': 100}, betting: true)
      : null,
  round: RoundState(
    question: _question,
    status: status,
    startedAtHostMicros: _start,
    timerRestartedAtHostMicros: restartedAt,
  ),
);

int _seconds(int s) => _start + Duration(seconds: s).inMicroseconds;

void main() {
  group('remainingAnswerTime', () {
    test('counts down from the time limit on the host clock', () {
      expect(
        remainingAnswerTime(_game(), _seconds(5)),
        const Duration(seconds: 15),
      );
      expect(remainingAnswerTime(_game(), _seconds(25)), Duration.zero);
    });

    test('follows a restarted answer clock', () {
      final game = _game(restartedAt: _seconds(30));
      expect(
        remainingAnswerTime(game, _seconds(32)),
        const Duration(seconds: 18),
      );
    });

    test('is hidden without a running answer clock', () {
      expect(remainingAnswerTime(const GameState(), _start), isNull);
      expect(
        remainingAnswerTime(_game(status: RoundStatus.locked), _seconds(1)),
        isNull,
      );
      expect(
        remainingAnswerTime(_game(status: RoundStatus.revealed), _seconds(1)),
        isNull,
      );
      expect(remainingAnswerTime(_game(betting: true), _seconds(1)), isNull);
      final untimed = _game().copyWith(
        round: _game().round.copyWith(
          question: const BuzzerQuestion(
            id: 'q',
            prompt: 'Buzz',
            timeLimit: Duration.zero,
          ),
        ),
      );
      expect(remainingAnswerTime(untimed, _seconds(1)), isNull);
    });

    test('stands still while the host is paused for recovery', () {
      final game = _game(paused: true, hostTime: _seconds(4));
      expect(
        remainingAnswerTime(game, _seconds(100)),
        const Duration(seconds: 16),
      );
    });
  });

  testWidgets('renders seconds and hides itself without a timer', (
    tester,
  ) async {
    var now = _seconds(8);
    Future<void> pump(GameState game) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundCountdown(game: game, hostNowMicros: () => now),
        ),
      ),
    );
    await pump(_game());
    expect(find.text('12 s'), findsOneWidget);
    now = _seconds(17);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3 s'), findsOneWidget);
    await pump(_game(status: RoundStatus.revealed));
    expect(find.byKey(const ValueKey('round-countdown')), findsNothing);
  });

  testWidgets('an expired clock shows a deep red 0 on phones', (tester) async {
    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoundCountdown(
              game: _game(),
              hostNowMicros: () => _seconds(30),
            ),
          ),
        ),
      );
    }

    addTearDown(tester.view.reset);
    await pumpAt(360);
    expect(find.text('0'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('0')).style?.color,
      const Color(0xFFB71C1C),
    );
    await pumpAt(1200);
    expect(find.text("Time's up"), findsOneWidget);
  });
}
