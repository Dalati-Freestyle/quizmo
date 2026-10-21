/// Round trip and redaction tests for the wire protocol.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';

void main() {
  group('client messages', () {
    test('round trip every variant through encode/decode', () {
      final messages = <ClientMessage>[
        const JoinRequest(
          name: 'Ada',
          teamId: 'red',
          clockOffsetMicros: -42,
          roundTripMicros: 18000,
        ),
        const SyncPing(clientSentAtMicros: 123456),
        const ClockReport(clockOffsetMicros: 7, roundTripMicros: 9),
        const SubmissionMessage(
          MultipleChoiceAnswer(
            playerId: 'p1',
            questionId: 'q1',
            clientTimestampMicros: 1000,
            clockOffsetMicros: 25,
            optionId: 'b',
          ),
        ),
        const SubmissionMessage(
          BuzzerPress(
            playerId: 'p1',
            questionId: 'q1',
            clientTimestampMicros: 1000,
            clockOffsetMicros: 25,
          ),
        ),
        const WatchRequest(),
        const LobbyRequest(),
        const JoinRequest(name: 'Ada', newTeamName: 'New team'),
        const RenameTeamMessage(name: 'New name'),
        const LeaveNotice(),
      ];

      for (final message in messages) {
        expect(ClientMessage.decode(message.encode()), message);
      }
    });

    test('rejects an unknown message tag', () {
      expect(
        () => ClientMessage.decode('{"type":"nope"}'),
        throwsA(isA<JsonContractException>()),
      );
    });
  });

  group('server messages', () {
    test('round trip every variant through encode/decode', () {
      final messages = <ServerMessage>[
        const WelcomeMessage(
          connectionId: 'conn-0',
          hostTimeMicros: 99,
          serverName: 'Quizmo Host',
        ),
        const JoinAcceptedMessage(playerId: 'p1', hostTimeMicros: 99),
        const WatchAcceptedMessage(),
        LobbySnapshotMessage(teams: sampleTeams, requiresTeam: true),
        const SyncPong(clientSentAtMicros: 1, hostTimeMicros: 2),
        const ProtocolErrorMessage(code: 'badRequest', message: 'nope'),
        GameSnapshotMessage(
          GameState(
            mode: const TeamMode(),
            players: const {'p1': Player(id: 'p1', name: 'Ada', teamId: 'red')},
            teams: sampleTeams,
            questionBank: sampleQuestionBank,
            round: const RoundState(
              question: buzzerSample,
              status: RoundStatus.acceptingAnswers,
              startedAtHostMicros: 1000,
            ),
            hostTimeMicros: 4242,
          ),
        ),
      ];

      for (final message in messages) {
        expect(ServerMessage.decode(message.encode()), message);
      }
    });
  });

  group('AnswerSubmission', () {
    test('derives the host timestamp from client clock minus offset', () {
      const press = BuzzerPress(
        playerId: 'p1',
        questionId: 'q1',
        clientTimestampMicros: 1000000,
        clockOffsetMicros: 250000,
      );

      expect(press.hostTimestampMicros, 750000);
    });

    test('re-attributes a submission to the trusted connection owner', () {
      const forged = MultipleChoiceAnswer(
        playerId: 'someone-else',
        questionId: 'q1',
        clientTimestampMicros: 10,
        clockOffsetMicros: 0,
        optionId: 'a',
      );

      expect(forged.withPlayerId('p1').playerId, 'p1');
    });
  });

  group('redaction', () {
    test('strips the solution and the upcoming question bank', () {
      const question = MultipleChoiceQuestion(
        id: 'q1',
        prompt: 'Which one?',
        options: [AnswerOption(id: 'a', label: 'A')],
        correctOptionId: 'a',
      );
      const game = GameState(
        questionBank: sampleQuestionBank,
        round: RoundState(
          question: question,
          status: RoundStatus.acceptingAnswers,
        ),
      );

      final redacted = game.redactedForPlayers();
      final onStage = redacted.round.question! as MultipleChoiceQuestion;

      expect(onStage.correctOptionId, isNull);
      expect(onStage.hasSolution, isFalse);
      expect(onStage.options, hasLength(1));
      expect(redacted.questionBank, isEmpty);
      final restored = GameState.fromJson(redacted.toJson());
      expect(restored.totalQuestionCount, sampleQuestionBank.length);
      expect(
        restored.redactedForPlayers().totalQuestionCount,
        sampleQuestionBank.length,
      );
      expect(restored.questionBank, isEmpty);
      final legacy = {...redacted.toJson()}..remove('totalQuestionCount');
      expect(GameState.fromJson(legacy).totalQuestionCount, 0);
    });

    test('keeps the solution once the round is revealed', () {
      const game = GameState(
        round: RoundState(question: buzzerSample, status: RoundStatus.revealed),
      );

      final onStage =
          game.redactedForPlayers().round.question! as BuzzerQuestion;

      expect(onStage.expectedAnswer, 'Gold');
    });
  });
}

const BuzzerQuestion buzzerSample = BuzzerQuestion(
  id: 'q-buzz',
  prompt: 'Symbol Au?',
  expectedAnswer: 'Gold',
);
