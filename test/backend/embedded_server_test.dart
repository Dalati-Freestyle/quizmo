/// End-to-end test of the embedded host.
///
/// Boots the real shelf server on an ephemeral port, connects two real
/// [QuizClient]s over loopback and verifies that the complete loop — HTTP clock
/// handshake, web socket join, buzzer race, latency adjusted ranking and state
/// broadcast — behaves as designed.
@TestOn('vm')
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';

void main() {
  late QuizEngineBloc engine;
  late EmbeddedServer server;
  late Uri baseUri;
  final clients = <QuizClient>[];

  /// Waits until [predicate] holds for the engine state, or fails.
  Future<void> waitFor(
    bool Function(QuizEngineState state) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (predicate(engine.state)) return;
    await engine.stream.firstWhere(predicate).timeout(timeout);
  }

  Future<QuizClient> joinAs(String name, {String? teamId}) async {
    final client = QuizClient(baseUri: baseUri);
    clients.add(client);
    await client.connect(name: name, teamId: teamId, handshakeProbes: 3);
    await waitFor(
      (state) => state.game.players.values.any((p) => p.name == name),
    );
    return client;
  }

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: sampleQuestionBank,
      teams: sampleTeams,
      buzzerGraceWindow: const Duration(milliseconds: 250),
    );
    server = EmbeddedServer(engine: engine, serverName: 'Test Host');
    // Port 0 lets the OS pick a free port, so parallel test runs cannot clash.
    final endpoint = await server.start(port: 0);
    baseUri = endpoint.loopbackUri;
  });

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    await server.dispose();
    await engine.close();
  });

  test('clients complete the clock handshake while joining', () async {
    final client = await joinAs('Ada');

    expect(client.playerId, isNotNull);
    expect(client.serverName, 'Test Host');
    expect(client.clock.isSynced, isTrue);
    // Loopback is fast, but the probe must have measured *something*.
    expect(client.clock.roundTripMicros, greaterThan(0));
  });

  test('broadcasts a redacted snapshot to every player', () async {
    final ada = await joinAs('Ada');
    await joinAs('Linus');

    final snapshot = ada.games.firstWhere(
      (game) => game.round.question?.id == 'q-capital',
    );
    engine.add(const StartRoundEvent('q-capital'));

    final game = await snapshot.timeout(const Duration(seconds: 5));
    final question = game.round.question! as MultipleChoiceQuestion;

    expect(question.options, hasLength(4));
    expect(
      question.correctOptionId,
      isNull,
      reason: 'players must not receive the solution before the reveal',
    );
    expect(game.questionBank, isEmpty);
    expect(game.players, hasLength(2));
  });

  test('crowns the fastest buzzer across two live clients', () async {
    final ada = await joinAs('Ada', teamId: 'team-red');
    final linus = await joinAs('Linus', teamId: 'team-blue');

    engine.add(const StartRoundEvent('q-buzzer-element'));
    await waitFor((state) => state.game.round.question != null);

    // Ada presses first; Linus follows inside the grace window.
    ada.pressBuzzer('q-buzzer-element');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    linus.pressBuzzer('q-buzzer-element');

    await waitFor((state) => state.game.round.status == RoundStatus.locked);

    final round = engine.state.game.round;
    expect(round.buzzerQueue, hasLength(2));
    expect(engine.state.game.activePlayer?.name, 'Ada');
    expect(
      round.buzzerQueue.first.hostTimestampMicros,
      lessThan(round.buzzerQueue.last.hostTimestampMicros),
    );

    engine.add(const JudgeBuzzerEvent(wasCorrect: true));
    await waitFor((state) => state.game.round.status == RoundStatus.revealed);

    expect(engine.state.game.teamScores['team-red'], 15);
    expect(engine.state.game.teamScores['team-blue'], 0);
  });

  test('scores a multiple choice round submitted over the socket', () async {
    final ada = await joinAs('Ada');
    final linus = await joinAs('Linus');

    engine.add(const StartRoundEvent('q-capital'));
    await waitFor((state) => state.game.round.question != null);

    ada.submitChoice(questionId: 'q-capital', optionId: 'b');
    linus.submitChoice(questionId: 'q-capital', optionId: 'a');

    await waitFor((state) => state.game.round.status == RoundStatus.revealed);

    final scores = engine.state.game.scores;
    expect(scores.scoreOf(ada.playerId!), greaterThanOrEqualTo(10));
    expect(scores.scoreOf(linus.playerId!), 0);
  });

  test('marks a player as disconnected when the socket closes', () async {
    final ada = await joinAs('Ada');
    final playerId = ada.playerId!;

    await ada.disconnect();
    await waitFor((state) => state.game.players[playerId]?.isConnected == false);

    expect(engine.state.game.connectedPlayers, isEmpty);
    expect(engine.state.game.players, hasLength(1));
  });
}

