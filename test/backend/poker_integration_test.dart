import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/protocol/messages.dart';

void main() {
  test(
    'players bet over sockets and TV receives chip balances without joining',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [
          TrueFalseQuestion(id: 'q', prompt: 'True?', correctAnswer: true),
        ],
        teams: const {'a': Team(id: 'a', name: 'A')},
        pokerStartingChips: 100,
      );
      final server = EmbeddedServer(engine: engine);
      final endpoint = await server.start(port: 0);
      final player = QuizClient(baseUri: endpoint.loopbackUri);
      final tv = QuizClient(baseUri: endpoint.loopbackUri);
      try {
        await player.connect(name: 'Player', teamId: 'a', handshakeProbes: 1);
        await tv.watch();
        expect(engine.state.game.players.length, 1);
        final started = player.games.firstWhere(
          (g) => g.poker?.betting ?? false,
        );
        engine.add(const StartRoundEvent('q'));
        await started.timeout(const Duration(seconds: 5));
        final bet = player.games.firstWhere((g) => g.poker!.wagers['a'] == 25);
        player.placePokerWager(questionId: 'q', wager: 25);
        expect(
          (await bet.timeout(const Duration(seconds: 5))).teamScores['a'],
          75,
        );
        final opened = player.games.firstWhere((g) => !g.poker!.betting);
        engine.add(const OpenPokerAnswersEvent());
        await opened.timeout(const Duration(seconds: 5));
        final result = tv.games.firstWhere(
          (g) => g.round.status == RoundStatus.revealed,
        );
        player.submitAnswer(
          (id, timestamp, offset) => TrueFalseAnswer(
            playerId: 'spoofed',
            questionId: 'q',
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            value: true,
          ),
        );
        final snapshot = await result.timeout(const Duration(seconds: 5));
        expect(snapshot.teamScores, {'a': 125});
        expect(snapshot.questionBank, isEmpty);
        expect(snapshot.round.answers.keys, [player.playerId]);
        expect(engine.state.game.players.length, 1);
      } finally {
        await player.dispose();
        await tv.dispose();
        await server.dispose();
        await engine.close();
      }
    },
  );

  test('wager wire message round-trips', () {
    const message = PokerWagerMessage(questionId: 'q', wager: 20);
    expect(ClientMessage.decode(message.encode()), message);
  });
}
