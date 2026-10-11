import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/protocol/messages.dart';

void main() {
  test('player picks and wagers over sockets; TV gets public results and playback controls', () async {
    final engine = QuizEngineBloc(
      mode: const TeamMode(),
      questionBank: const [
        TrueFalseQuestion(id: 'q', prompt: 'True?', correctAnswer: true),
      ],
      teams: const {'a': Team(id: 'a', name: 'Alpha')},
      jeopardyBoard: const JeopardyBoard(
        rowPoints: [200],
        categories: [
          JeopardyCategory(
            name: 'Category',
            cells: [JeopardyCell(questionId: 'q', isDailyDouble: true)],
          ),
        ],
      ),
    );
    engine.add(const StartGameEvent());
    await pumpEventQueue();
    final server = EmbeddedServer(engine: engine);
    final endpoint = await server.start(port: 0);
    final player = QuizClient(baseUri: endpoint.loopbackUri);
    final tv = QuizClient(baseUri: endpoint.loopbackUri);
    try {
      await player.connect(name: 'Player', teamId: 'a', handshakeProbes: 1);
      await tv.watch();
      final requested = player.games.firstWhere(
        (g) => g.jeopardy?.pendingPickQuestionId == 'q',
      );
      player.selectJeopardyCell('q');
      final request = await requested.timeout(const Duration(seconds: 5));
      expect(request.round.question, isNull);
      expect(request.jeopardy!.pendingDailyDoubleId, isNull);
      final pending = player.games.firstWhere(
        (g) => g.jeopardy?.pendingDailyDoubleId == 'q',
      );
      engine.add(
        ConfirmQuestionPickEvent(
          questionId: 'q',
          playerId: player.playerId!,
          accepted: true,
        ),
      );
      final board = await pending.timeout(const Duration(seconds: 5));
      expect(board.round.question, isNull);
      expect(board.jeopardy!.board.isDailyDouble('q'), isFalse);
      final opened = player.games.firstWhere(
        (g) => g.round.status == RoundStatus.acceptingAnswers,
      );
      player.placeDailyDoubleWager('q', 125);
      final question = await opened.timeout(const Duration(seconds: 5));
      expect(question.jeopardy!.activePoints, 125);
      expect(
        (question.round.question as TrueFalseQuestion).correctAnswer,
        isNull,
      );
      final paused = tv.games.firstWhere((g) => g.tvMediaPaused);
      engine.add(const ControlTvMediaEvent(TvMediaAction.pause));
      expect(
        (await paused.timeout(const Duration(seconds: 5))).tvMediaPaused,
        isTrue,
      );
      final result = tv.games.firstWhere(
        (g) => g.round.status == RoundStatus.revealed,
      );
      player.submitAnswer(
        (id, timestamp, offset) => TrueFalseAnswer(
          playerId: id,
          questionId: 'q',
          clientTimestampMicros: timestamp,
          clockOffsetMicros: offset,
          value: true,
        ),
      );
      final snapshot = await result.timeout(const Duration(seconds: 5));
      expect(snapshot.teamScores, {'a': 125});
      expect(snapshot.questionWinners, {'q': 'Alpha'});
      expect(snapshot.tvMediaPaused, isFalse);
      expect(snapshot.questionBank, isEmpty);
      expect(engine.state.game.players.length, 1);
    } finally {
      await player.dispose();
      await tv.dispose();
      await server.dispose();
      await engine.close();
    }
  });

  test('Jeopardy message payloads round-trip', () {
    for (final message in <ClientMessage>[
      const JeopardyPickMessage('q'),
      const DailyDoubleWagerMessage(questionId: 'q', wager: 125),
    ]) {
      expect(ClientMessage.decode(message.encode()), message);
    }
  });
}
