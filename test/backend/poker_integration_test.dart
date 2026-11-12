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

  test('private acceptance survives reconnect without revealing poker answers to players or TV', () async {
    final engine = QuizEngineBloc(
      questionBank: const [
        TrueFalseQuestion(id: 'q', prompt: 'True?', correctAnswer: true),
      ],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      pokerStartingChips: 100,
    );
    final server = EmbeddedServer(engine: engine);
    final endpoint = await server.start(port: 0);
    final player = QuizClient(baseUri: endpoint.loopbackUri);
    final other = QuizClient(baseUri: endpoint.loopbackUri);
    final tv = QuizClient(baseUri: endpoint.loopbackUri);
    final returning = QuizClient(baseUri: endpoint.loopbackUri);
    addTearDown(() async {
      await player.dispose();
      await other.dispose();
      await tv.dispose();
      await returning.dispose();
      await server.dispose();
      await engine.close();
    });
    await player.connect(name: 'Ada', teamId: 'a', handshakeProbes: 1);
    await other.connect(name: 'Bob', teamId: 'b', handshakeProbes: 1);
    await tv.watch();
    final betting = player.games.firstWhere((game) => game.poker!.betting);
    engine.add(const StartRoundEvent('q'));
    await betting;
    final wagered = player.games.firstWhere(
      (game) => game.poker!.wagers['a'] == 25,
    );
    player.placePokerWager(questionId: 'q', wager: 25);
    await wagered;
    final otherWagered = other.games.firstWhere(
      (game) => game.poker!.wagers['b'] == 25,
    );
    other.placePokerWager(questionId: 'q', wager: 25);
    await otherWagered;
    final opened = player.games.firstWhere((game) => !game.poker!.betting);
    engine.add(const OpenPokerAnswersEvent());
    await opened;
    final own = player.snapshots.firstWhere(
      (snapshot) => snapshot.ownSubmissionAccepted == true,
    );
    final watched = tv.snapshots.first;
    final others = other.snapshots.first;
    player.submitAnswer(
      (id, timestamp, offset) => TrueFalseAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: timestamp,
        clockOffsetMicros: offset,
        value: true,
      ),
    );
    final receipt = await own.timeout(const Duration(seconds: 5));
    expect(receipt.game.round.answers, isEmpty);
    expect((await watched).game.round.answers, isEmpty);
    expect((await others).ownSubmissionAccepted, isFalse);
    final restored = returning.snapshots.firstWhere(
      (snapshot) => snapshot.ownSubmissionAccepted == true,
    );
    await returning.connect(
      name: 'Ada',
      resumePlayerId: player.playerId,
      resumeToken: player.resumeToken,
      handshakeProbes: 1,
    );
    final restoredReceipt = await restored.timeout(const Duration(seconds: 5));
    expect(restoredReceipt.game.round.answers, isEmpty);
    expect(returning.playerId, player.playerId);
    expect(engine.state.game.round.answers, hasLength(1));
  });
}
