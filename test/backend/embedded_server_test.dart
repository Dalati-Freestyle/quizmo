/// End-to-end test of the embedded host.
///
/// Boots the real shelf server on an ephemeral port, connects two real
/// [QuizClient]s over loopback and verifies that the complete loop — HTTP clock
/// handshake, web socket join, buzzer race, latency adjusted ranking and state
/// broadcast — behaves as designed.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/backend/web_client_bundle.dart';
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
    server = EmbeddedServer(
      engine: engine,
      serverName: 'Test Host',
      webClient: InMemoryWebClientBundle({
        'index.html': Uint8List.fromList(utf8.encode('<html>player</html>')),
        'main.dart.js': Uint8List.fromList(utf8.encode('console.log(1)')),
      }),
    );
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

  test('lobby supplies actual teams without registering a player, then joins on the same socket', () async {
    final client = QuizClient(baseUri: baseUri);
    clients.add(client);
    final lobby = client.lobbies.first;
    await client.browseLobby();
    expect((await lobby).teams, sampleTeams);
    expect(engine.state.game.players, isEmpty);
    expect(client.playerId, isNull);
    await client.connect(
      name: 'Ada',
      teamId: sampleTeams.keys.last,
      handshakeProbes: 1,
    );
    await waitFor(
      (state) =>
          state.game.players[client.playerId]?.teamId == sampleTeams.keys.last,
    );
    expect(client.clock.isSynced, isTrue);
    expect(server.connectionCount, 1);
  });

  test(
    'new teams and member renames reach the lobby, players and TV',
    () async {
      final lobbyClient = QuizClient(baseUri: baseUri);
      final creator = QuizClient(baseUri: baseUri);
      final tv = QuizClient(baseUri: baseUri);
      clients.addAll([lobbyClient, creator, tv]);
      await lobbyClient.browseLobby();
      await creator.browseLobby();
      await tv.watch();
      final newTeam = lobbyClient.lobbies.firstWhere(
        (message) => message.teams.values.any((team) => team.name == 'Owls'),
      );
      await creator.connect(
        name: 'Ada',
        newTeamName: ' Owls ',
        handshakeProbes: 1,
      );
      final team = (await newTeam).teams.values.singleWhere(
        (team) => team.name == 'Owls',
      );
      await waitFor(
        (state) => state.game.players[creator.playerId]?.teamId == team.id,
      );
      final member = await joinAs('Linus', teamId: team.id);
      final renamedLobby = lobbyClient.lobbies.firstWhere(
        (message) => message.teams[team.id]?.name == 'Night Owls',
      );
      final renamedPlayer = creator.games.firstWhere(
        (game) => game.teams[team.id]?.name == 'Night Owls',
      );
      final renamedTv = tv.games.firstWhere(
        (game) => game.teams[team.id]?.name == 'Night Owls',
      );
      member.renameTeam('Night Owls');
      await Future.wait([renamedLobby, renamedPlayer, renamedTv])
          .timeout(const Duration(seconds: 5));
      creator.renameTeam('Ada Owls');
      await waitFor((state) => state.game.teams[team.id]?.name == 'Ada Owls');
      expect(engine.state.game.teams[team.id]?.id, team.id);
    },
  );

  test(
    'invalid team selection can be corrected without reconnecting',
    () async {
      final client = QuizClient(baseUri: baseUri);
      clients.add(client);
      await client.browseLobby();
      await expectLater(
        client.connect(name: 'Ada', teamId: 'missing', handshakeProbes: 1),
        throwsStateError,
      );
      expect(engine.state.game.players, isEmpty);
      expect(client.playerId, isNull);
      await client.connect(
        name: 'Ada',
        teamId: sampleTeams.keys.first,
        handshakeProbes: 1,
      );
      await waitFor((state) => state.game.players.containsKey(client.playerId));
    },
  );

  test('solo players cannot rename another team', () async {
    final solo = await joinAs('Solo');
    final rejected = solo.errors.first;
    solo.renameTeam('Stolen');
    expect((await rejected).code, 'notInTeam');
    expect(engine.state.game.teams, sampleTeams);
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

    final visibleToAda = ada.games.firstWhere(
      (game) => game.round.question?.id == 'q-capital',
    );
    final visibleToLinus = linus.games.firstWhere(
      (game) => game.round.question?.id == 'q-capital',
    );
    engine.add(const StartRoundEvent('q-capital'));
    await Future.wait([visibleToAda, visibleToLinus])
        .timeout(const Duration(seconds: 5));

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
    await waitFor(
      (state) => state.game.players[playerId]?.isConnected == false,
    );

    expect(engine.state.game.connectedPlayers, isEmpty);
    expect(engine.state.game.players, hasLength(1));
  });

  group('spectator (TV) clients', () {
    Future<QuizClient> watchAsTv() async {
      final client = QuizClient(baseUri: baseUri);
      clients.add(client);
      await client.watch();
      return client;
    }

    test(
      'watch without joining the roster and receive live snapshots',
      () async {
        final tv = await watchAsTv();

        expect(tv.status, QuizClientStatus.connected);
        expect(tv.playerId, isNull);
        expect(engine.state.game.players, isEmpty);

        final snapshot = tv.games.firstWhere(
          (game) => game.round.question?.id == 'q-capital',
        );
        engine.add(const StartRoundEvent('q-capital'));

        final game = await snapshot.timeout(const Duration(seconds: 5));
        final question = game.round.question! as MultipleChoiceQuestion;
        expect(
          question.correctOptionId,
          isNull,
          reason: 'TV must stay redacted',
        );
        expect(game.questionBank, isEmpty);
      },
    );

    test('cannot influence a round', () async {
      final tv = await watchAsTv();
      engine.add(const StartRoundEvent('q-buzzer-element'));
      await waitFor((state) => state.game.round.question != null);

      tv.pressBuzzer('q-buzzer-element');
      tv.submitChoice(questionId: 'q-capital', optionId: 'a');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(engine.state.game.round.buzzerQueue, isEmpty);
      expect(engine.state.game.round.answers, isEmpty);
    });

    test('leaving does not touch the player roster', () async {
      final ada = await joinAs('Ada');
      final tv = await watchAsTv();

      await tv.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(engine.state.game.connectedPlayers, hasLength(1));
      expect(engine.state.game.players.containsKey(ada.playerId), isTrue);
    });

    test('is served at /tv through the single page app fallback', () async {
      final response = await http.get(baseUri.resolve('/tv'));

      expect(response.statusCode, 200);
      expect(response.body, '<html>player</html>');
    });
  });

  group('web client hosting', () {
    test('serves the bundled player at the site root', () async {
      expect(server.servesWebClient, isTrue);

      final response = await http.get(baseUri);

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('text/html'));
      expect(response.body, '<html>player</html>');
    });

    test('keeps the API reachable behind the catch-all route', () async {
      final response = await http.get(baseUri.resolve('/api/health'));

      expect(response.statusCode, 200);
      expect(
        (jsonDecode(response.body) as Map<String, dynamic>)['serverName'],
        'Test Host',
      );
    });

    test('serves a placeholder page when no bundle is configured', () async {
      final bare = EmbeddedServer(engine: engine, serverName: 'Bare Host');
      addTearDown(bare.dispose);
      final endpoint = await bare.start(port: 0);

      expect(bare.servesWebClient, isFalse);

      final response = await http.get(endpoint.loopbackUri);

      expect(response.statusCode, 200);
      expect(response.body, contains('Bare Host'));

      final missing = await http.get(endpoint.loopbackUri.resolve('/nope.js'));
      expect(missing.statusCode, 404);
    });
  });
}
