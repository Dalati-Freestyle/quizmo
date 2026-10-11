import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/player_session_store.dart';

class MemorySessionStore extends PlayerSessionStore {
  SavedPlayerSession? session;
  @override
  Future<SavedPlayerSession?> read() async => session;
  @override
  Future<void> save(SavedPlayerSession value) async {
    session = value;
  }

  @override
  Future<void> clear() async {
    session = null;
  }
}

void main() {
  late QuizEngineBloc engine;
  late EmbeddedServer server;
  late Uri host;
  final clients = <QuizClient>[];
  Future<void> waitFor(bool Function(GameState) predicate) async {
    if (predicate(engine.state.game)) return;
    await engine.stream
        .firstWhere((s) => predicate(s.game))
        .timeout(const Duration(seconds: 5));
  }

  Future<QuizClient> join() async {
    final client = QuizClient(baseUri: host);
    clients.add(client);
    await client.connect(name: 'Ada', teamId: 'a', handshakeProbes: 1);
    await waitFor((g) => g.players.containsKey(client.playerId));
    return client;
  }

  setUp(() async {
    engine = QuizEngineBloc(
      questionBank: const [
        TrueFalseQuestion(
          id: 'q',
          prompt: '?',
          correctAnswer: true,
          scoringRule: FixedPointsRule(correctPoints: 10),
        ),
      ],
      teams: const {'a': Team(id: 'a', name: 'A')},
    );
    server = EmbeddedServer(engine: engine);
    host = (await server.start(port: 0)).loopbackUri;
  });
  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    await server.dispose();
    await engine.close();
  });
  test('refresh replaces old socket, keeps score/team and old close cannot disconnect new socket', () async {
    final old = await join();
    final id = old.playerId!;
    final token = old.resumeToken!;
    engine.add(const StartRoundEvent('q'));
    await waitFor((g) => g.round.status.acceptsInput);
    old.submitAnswer(
      (id, t, o) => TrueFalseAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: t,
        clockOffsetMicros: o,
        value: true,
      ),
    );
    await waitFor((g) => g.scores.scoreOf(id) == 10);
    final returning = QuizClient(baseUri: host);
    clients.add(returning);
    await returning.connect(
      name: 'Ada',
      resumePlayerId: id,
      resumeToken: token,
      handshakeProbes: 1,
    );
    await old.dispose();
    clients.remove(old);
    await pumpEventQueue();
    expect(engine.state.game.players.keys, [id]);
    expect(engine.state.game.players[id]!.isConnected, isTrue);
    expect(engine.state.game.players[id]!.teamId, 'a');
    expect(engine.state.game.scores.scoreOf(id), 10);
  });
  test('resume rejects public ID without secret and kicked ID cannot be recreated by resume', () async {
    final original = await join();
    final id = original.playerId!;
    final token = original.resumeToken!;
    final impostor = QuizClient(baseUri: host);
    clients.add(impostor);
    await expectLater(
      impostor.connect(name: 'Ada', resumePlayerId: id, handshakeProbes: 1),
      throwsStateError,
    );
    expect(engine.state.game.players, hasLength(1));
    final kicked = original.errors.first;
    engine.add(KickPlayerEvent(id));
    expect((await kicked).code, 'kicked');
    await waitFor((g) => !g.players.containsKey(id));
    await expectLater(
      impostor.connect(
        name: 'Ada',
        resumePlayerId: id,
        resumeToken: token,
        handshakeProbes: 1,
      ),
      throwsStateError,
    );
    expect(engine.state.game.players, isEmpty);
  });
  test('persisted session restores after client controller is recreated and explicit leave clears it', () async {
    final store = MemorySessionStore();
    final first = PlayerSessionCubit(store: store);
    await first.connect(baseUri: host, name: 'Ada', teamId: 'a');
    await waitFor((g) => g.players.containsKey(first.state.playerId));
    await pumpEventQueue();
    final id = first.state.playerId!;
    expect(store.session?.playerId, id);
    await first.close();
    await waitFor((g) => !g.players[id]!.isConnected);
    final second = PlayerSessionCubit(store: store);
    addTearDown(second.close);
    await second.restore(host: host);
    await waitFor((g) => g.players[id]!.isConnected);
    expect(second.state.playerId, id);
    expect(engine.state.game.players, hasLength(1));
    await second.disconnect();
    expect(store.session, isNull);
  });
  test('lost transport automatically resumes the same player and restores the submitted answer', () async {
    final store = MemorySessionStore();
    final client = QuizClient(baseUri: host);
    final session = PlayerSessionCubit(
      store: store,
      createClient: (_) => client,
    );
    addTearDown(session.close);
    await session.connect(baseUri: host, name: 'Ada', teamId: 'a');
    final id = session.state.playerId!;
    await waitFor((g) => g.players.containsKey(id));
    // A second participant keeps the question open after Ada submits.
    await join();
    engine.add(const StartRoundEvent('q'));
    await waitFor((g) => g.round.status.acceptsInput);
    await pumpEventQueue();
    session.submit(
      (id, t, o) => TrueFalseAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: t,
        clockOffsetMicros: o,
        value: true,
      ),
    );
    await waitFor((g) => g.round.answers.containsKey(id));
    await client.disconnect();
    await waitFor((g) => !g.players[id]!.isConnected);
    await waitFor((g) => g.players[id]!.isConnected);
    await pumpEventQueue();
    expect(session.state.playerId, id);
    expect(session.state.lastSubmittedOptionId, 'submitted');
    expect(engine.state.game.players, hasLength(2));
  });
  test(
    'disposing during the clock handshake cannot open a new socket',
    () async {
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      final mock = MockClient((request) {
        entered.complete();
        return response.future;
      });
      final client = QuizClient(baseUri: host, httpClient: mock);
      final connecting = expectLater(
        client.connect(name: 'Ada', handshakeProbes: 1),
        throwsStateError,
      );
      await entered.future;
      await client.dispose();
      response.complete(
        http.Response('{"clientSentAtMicros": 0, "hostTimeMicros": 0}', 200),
      );
      await connecting;
      expect(server.connectionCount, 0);
      mock.close();
    },
  );
}
