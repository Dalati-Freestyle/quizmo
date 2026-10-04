/// Countdown maths and reconnect behaviour of the spectator controller.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';

void main() {
  group('SpectatorSessionState.remainingTime', () {
    final receivedAt = DateTime(2030, 1, 1, 12);

    SpectatorSessionState stateWith(RoundStatus status, {int? hostTime}) =>
        SpectatorSessionState(
          snapshotReceivedAt: receivedAt,
          game: GameState(
            hostTimeMicros: hostTime ?? 15 * Duration.microsecondsPerSecond,
            round: RoundState(
              status: status,
              startedAtHostMicros: 5 * Duration.microsecondsPerSecond,
              question: const MultipleChoiceQuestion(
                id: 'q',
                prompt: '?',
                options: [AnswerOption(id: 'a', label: 'A')],
                timeLimit: Duration(seconds: 30),
              ),
            ),
          ),
        );

    test('combines host elapsed time with the local time since arrival', () {
      final state = stateWith(RoundStatus.acceptingAnswers);

      // 10 s were already over when the snapshot arrived, plus 3 s locally.
      expect(
        state.remainingTime(receivedAt.add(const Duration(seconds: 3))),
        const Duration(seconds: 17),
      );
    });

    test('never goes negative', () {
      final state = stateWith(RoundStatus.acceptingAnswers);

      expect(
        state.remainingTime(receivedAt.add(const Duration(minutes: 5))),
        Duration.zero,
      );
    });

    test('is null unless the round accepts answers', () {
      expect(
        stateWith(RoundStatus.revealed).remainingTime(receivedAt),
        isNull,
      );
      expect(const SpectatorSessionState().remainingTime(receivedAt), isNull);
    });
  });

  test('keeps retrying with a growing back-off while the host is away', () async {
    final cubit = SpectatorSessionCubit(
      baseUri: Uri.parse('http://127.0.0.1:1'),
      clientFactory: _UnreachableClient.new,
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 40),
    );
    addTearDown(cubit.close);

    await cubit.start();
    final attempts = await cubit.stream
        .map((state) => state.reconnectAttempt)
        .firstWhere((attempt) => attempt >= 3)
        .timeout(const Duration(seconds: 5));

    expect(attempts, greaterThanOrEqualTo(3));
    expect(cubit.state.isConnected, isFalse);
    final failure = await cubit.stream
        .firstWhere((state) => state.status == QuizClientStatus.failed)
        .timeout(const Duration(seconds: 5));
    expect(failure.error, contains('host is away'));
  });
}

/// A client whose host never answers.
class _UnreachableClient extends QuizClient {
  _UnreachableClient(Uri baseUri) : super(baseUri: baseUri);

  @override
  Future<void> watch({Duration joinTimeout = const Duration(seconds: 10)}) =>
      Future<void>.error(StateError('host is away'));
}

