@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/backend/internet_server.dart';
import 'package:quizmo/backend/relay_host.dart';
import 'package:quizmo/backend/web_client_bundle.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/data/session_recovery.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/net/session_uri.dart';
import 'package:web_socket_channel/io.dart';

import '../helpers/memory_recovery_store.dart';

void main() {
  final quiz = createSampleQuiz(DateTime.utc(2026))
      .copyWith(teams: sampleTeams.values.toList());
  final engines = <QuizEngineBloc>[];
  final recoveries = <SessionRecovery>[];
  final clients = <QuizClient>[];
  final stops = <Future<void> Function()>[];

  QuizEngineBloc engine({SessionCheckpoint? saved}) {
    final value = QuizEngineBloc(
      questionBank: quiz.questions,
      teams: quiz.teamsById,
      mode: const TeamMode(),
      recoverySessionId: saved?.sessionId ?? 'persistent-test-session-1234',
      restoredGame: saved?.pausedGame(),
      resumeTokenHashes: saved?.resumeTokenHashes ?? const {},
    );
    engines.add(value);
    return value;
  }

  Future<SessionRecovery> persist(
    QuizEngineBloc engine,
    MemoryRecoveryStore store, {
    SessionCheckpoint? saved,
  }) async {
    final recovery = SessionRecovery(
      engine: engine,
      quiz: quiz,
      store: store,
      restored: saved,
    );
    recoveries.add(recovery);
    await recovery.start();
    return recovery;
  }

  QuizClient client(Uri uri) {
    final value = QuizClient(baseUri: uri);
    clients.add(value);
    return value;
  }

  Future<void> wait(
    QuizEngineBloc engine,
    bool Function(GameState) predicate,
  ) async {
    if (predicate(engine.state.game)) return;
    await engine.stream
        .firstWhere((s) => predicate(s.game))
        .timeout(const Duration(seconds: 5));
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    for (final stop in stops.reversed) {
      await stop();
    }
    for (final recovery in recoveries) {
      await recovery.close();
    }
    for (final engine in engines) {
      await engine.close();
    }
    clients.clear();
    stops.clear();
    recoveries.clear();
    engines.clear();
  });

  test('player and REST snapshots never acknowledge answers or reveal solutions before commit', () async {
    final store = MemoryRecoveryStore();
    final original = engine();
    final recovery = await persist(original, store);
    final server = EmbeddedServer(engine: original);
    stops.add(server.dispose);
    final uri = (await server.start(port: 0)).loopbackUri;
    final player = client(uri);
    await player.connect(name: 'Ada', teamId: 'team-red', handshakeProbes: 1);
    original.add(const StartRoundEvent('q-capital'));
    await wait(original, (g) => g.round.status.acceptsInput);
    await recovery.checkpoint();
    var answerPublished = false;
    final subscription = player.games.listen((g) {
      if (g.round.answers.isNotEmpty) answerPublished = true;
    });
    final barrier = Completer<void>();
    store.writeBarrier = barrier;
    try {
      player.submitChoice(questionId: 'q-capital', optionId: 'b');
      await wait(original, (g) => g.round.answers.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(answerPublished, isFalse);
      final response = jsonDecode(
        (await http.get(uri.resolve('/api/state'))).body,
      ) as Map<String, dynamic>;
      final round = response['round'] as Map<String, dynamic>;
      expect(round['answers'], isEmpty);
      expect(
        (round['question'] as Map<String, dynamic>)['correctOptionId'],
        isNull,
      );
    } finally {
      barrier.complete();
    }
    await recovery.checkpoint();
    await wait(original, (g) => g.round.status == RoundStatus.revealed);
    await pumpEventQueue();
    expect(answerPublished, isTrue);
    expect(store.record!.decode().game.round.answers, isNotEmpty);
    await subscription.cancel();
  });

  test('LAN restart restores credentials, team and accepted answer; reveal is exactly once', () async {
    final store = MemoryRecoveryStore();
    final original = engine();
    final recovery = await persist(original, store);
    final server = EmbeddedServer(engine: original);
    stops.add(server.dispose);
    final oldUri = (await server.start(port: 0)).loopbackUri;
    final player = client(oldUri);
    await player.connect(name: 'Ada', teamId: 'team-red', handshakeProbes: 1);
    final other = client(oldUri);
    await other.connect(name: 'Bob', teamId: 'team-blue', handshakeProbes: 1);
    final id = player.playerId!;
    final token = player.resumeToken!;
    original.add(const StartRoundEvent('q-capital'));
    await wait(original, (g) => g.round.status.acceptsInput);
    player.submitChoice(questionId: 'q-capital', optionId: 'b');
    await wait(original, (g) => g.round.answers.containsKey(id));
    await recovery.checkpoint();
    final saved = store.record!.decode();
    await server.dispose();
    await recovery.close();
    final restored = engine(saved: saved);
    await persist(restored, store, saved: saved);
    final newServer = EmbeddedServer(engine: restored);
    stops.add(newServer.dispose);
    final newUri = (await newServer.start(port: 0)).loopbackUri;
    expect(samePlayerSession(oldUri, newUri), isTrue);
    final intruder = client(newUri);
    await expectLater(
      intruder.connect(
        name: 'Ada',
        resumePlayerId: id,
        resumeToken: 'wrong',
        handshakeProbes: 1,
      ),
      throwsStateError,
    );
    final returning = client(newUri);
    await returning.connect(
      name: 'Ada',
      resumePlayerId: id,
      resumeToken: token,
      handshakeProbes: 1,
    );
    expect(returning.playerId, id);
    expect(restored.state.game.players[id]!.teamId, 'team-red');
    expect(restored.state.game.round.answers, saved.game.round.answers);
    final tv = client(newUri);
    await tv.watch();
    final snapshot = tv.games.first;
    restored.add(
      const TimeSyncEvent(
        playerId: 'one',
        clockOffsetMicros: 0,
        roundTripMicros: 1,
      ),
    );
    restored.add(const PlayerLeftEvent('nonexistent'));
    final redactedFuture = returning.games.first;
    restored.add(
      PlayerJoinedEvent(
        restored.state.game.players[id]!.copyWith(roundTripMicros: 5),
      ),
    );
    final redacted = await redactedFuture.timeout(const Duration(seconds: 5));
    expect(
      (redacted.round.question! as MultipleChoiceQuestion).correctOptionId,
      isNull,
    );
    expect(redacted.round.question!.solutionMedia, isEmpty);
    expect((await snapshot).questionBank, isEmpty);
    restored.add(const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime));
    await wait(restored, (g) => !g.recoveryPaused);
    returning.submitChoice(questionId: 'q-capital', optionId: 'a');
    await pumpEventQueue();
    expect(
      (restored.state.game.round.answers[id] as MultipleChoiceAnswer).optionId,
      'b',
    );
    restored.add(const RevealRoundEvent());
    await wait(restored, (g) => g.round.status == RoundStatus.revealed);
    final points = restored.state.game.scores.scoreOf(id);
    expect(points, greaterThan(0));
    restored.add(const RevealRoundEvent());
    await pumpEventQueue();
    expect(restored.state.game.scores.scoreOf(id), points);
  });

  test(
    'explicit verified rebind keeps original ID and revokes lost credentials',
    () async {
      final store = MemoryRecoveryStore();
      final original = engine();
      final recovery = await persist(original, store);
      final server = EmbeddedServer(engine: original);
      stops.add(server.dispose);
      final uri = (await server.start(port: 0)).loopbackUri;
      final oldPlayer = client(uri);
      await oldPlayer.connect(
        name: 'Original',
        teamId: 'team-red',
        handshakeProbes: 1,
      );
      final originalId = oldPlayer.playerId!;
      final oldToken = oldPlayer.resumeToken!;
      await recovery.checkpoint();
      final saved = store.record!.decode();
      await server.dispose();
      await recovery.close();
      final restored = engine(saved: saved);
      final resumed = await persist(restored, store, saved: saved);
      final newServer = EmbeddedServer(engine: restored);
      stops.add(newServer.dispose);
      final newUri = (await newServer.start(port: 0)).loopbackUri;
      final replacement = client(newUri);
      final unexpectedTeam = client(newUri);
      await expectLater(
        unexpectedTeam.connect(
          name: 'New browser',
          newTeamName: 'Unwanted team',
          handshakeProbes: 1,
        ),
        throwsStateError,
      );
      expect(restored.state.game.teams, saved.game.teams);
      await replacement.connect(
        name: 'New browser',
        teamId: 'team-blue',
        handshakeProbes: 1,
      );
      final temporaryId = replacement.playerId!;
      final token = replacement.resumeToken!;
      expect(restored.state.game.recoveryPaused, isTrue);
      expect(restored.state.game.players[originalId]!.isConnected, isFalse);
      expect(restored.state.game.players[temporaryId]!.isConnected, isTrue);
      expect(restored.recoveryPlayerIds, contains(originalId));
      expect(restored.recoveryPlayerIds, isNot(contains(temporaryId)));
      expect(restored.resumeTokenHashes[temporaryId], isNotNull);
      final accepted = replacement.statuses.firstWhere(
        (_) => replacement.playerId == originalId,
      );
      restored.add(
        RebindRecoveredPlayerEvent(
          playerId: originalId,
          temporaryPlayerId: temporaryId,
        ),
      );
      await pumpEventQueue();
      expect(
        restored.state.notice,
        isNot('This participant cannot be reassigned.'),
      );
      expect(restored.state.game.players.keys, [originalId]);
      expect(resumed.lastError, isNull);
      await accepted.timeout(const Duration(seconds: 5));
      expect(replacement.playerId, originalId);
      expect(restored.state.game.players[originalId]!.teamId, 'team-red');
      expect(restored.state.game.players, hasLength(1));
      expect(restored.state.game.players.containsKey(temporaryId), isFalse);
      await resumed.checkpoint();
      expect(
        store.record!.decode().resumeTokenHashes[originalId],
        hashResumeToken(token),
      );
      final oldAccess = client(newUri);
      await expectLater(
        oldAccess.connect(
          name: 'Original',
          resumePlayerId: originalId,
          resumeToken: oldToken,
          handshakeProbes: 1,
        ),
        throwsStateError,
      );
      expect(
        jsonEncode(restored.state.game.redactedForPlayers().toJson()),
        isNot(contains(token)),
      );
    },
  );

  test('relay loss pauses the engine; recovery uses a new room, old link fails, same private identity resumes', () async {
    const origin = 'https://quiz.example.com';
    final relay = InternetServer(
      publicOrigin: Uri.parse(origin),
      webClient: InMemoryWebClientBundle({
        'index.html': Uint8List.fromList(utf8.encode('<html>Quizmo</html>')),
      }),
    );
    final port = await relay.start(port: 0);
    stops.add(relay.close);
    final base = Uri.parse('http://127.0.0.1:$port');
    Future<RelayHost> host(QuizEngineBloc engine) async {
      final result = RelayHost(
        engine: engine,
        origin: base,
        connect: (uri) =>
            IOWebSocketChannel.connect(uri, headers: {'Origin': origin}),
      );
      stops.add(result.dispose);
      await result.start();
      return result;
    }

    final store = MemoryRecoveryStore();
    final original = engine();
    final recovery = await persist(original, store);
    final oldHost = await host(original);
    final oldUri = oldHost.endpoint!.lanUri;
    final player = client(oldUri);
    await player.connect(name: 'Ada', teamId: 'team-red', handshakeProbes: 1);
    final id = player.playerId!;
    final token = player.resumeToken!;
    original.add(const StartRoundEvent('q-capital'));
    await wait(original, (g) => g.round.status.acceptsInput);
    await recovery.checkpoint();
    await relay.close();
    await wait(original, (g) => g.recoveryPaused);
    await oldHost.dispose();
    await recovery.close();
    final restartedPort = await relay.start(port: port);
    expect(restartedPort, port);
    final latest = store.record!.decode();
    final restored = engine(saved: latest);
    await persist(restored, store, saved: latest);
    final newHost = await host(restored);
    final newUri = newHost.endpoint!.lanUri;
    expect(newUri.path, isNot(oldUri.path));
    expect(samePlayerSession(oldUri, newUri), isTrue);
    expect(
      (await http.get(sessionSocketUri(oldUri).replace(scheme: 'http')))
          .statusCode,
      404,
    );
    final returning = client(newUri);
    await returning.connect(
      name: 'Ada',
      resumePlayerId: id,
      resumeToken: token,
      handshakeProbes: 1,
    );
    expect(returning.playerId, id);
    final refresh = client(newUri);
    await refresh.connect(
      name: 'Ada',
      resumePlayerId: id,
      resumeToken: token,
      handshakeProbes: 1,
    );
    expect(refresh.playerId, id);
    expect(restored.state.game.players, hasLength(1));
    expect(restored.state.game.recoveryPaused, isTrue);
  });
}
