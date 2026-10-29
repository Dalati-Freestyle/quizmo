import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/embedded_server.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/backend/server_contract.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/session_access.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/protocol/messages.dart';

class Peer {
  Peer(SocketHub hub) {
    hub.attach(
      stream: input.stream,
      send: (frame) => messages.add(ServerMessage.decode(frame)),
      close: () async {
        closed = true;
      },
    );
  }
  final input = StreamController<dynamic>();
  final messages = <ServerMessage>[];
  bool closed = false;
  Future<void> send(ClientMessage message) async {
    input.add(message.encode());
    await pumpEventQueue();
  }

  ProtocolErrorMessage get error =>
      messages.whereType<ProtocolErrorMessage>().last;
  JoinAcceptedMessage get accepted =>
      messages.whereType<JoinAcceptedMessage>().last;
}

void main() {
  test('access recovery rejects missing policy fields instead of silently unlocking', () {
    final settings = const SessionAccessState(locked: true).toJson();
    for (final key in settings.keys) {
      expect(
        () => SessionAccessState.fromJson({...settings}..remove(key)),
        throwsA(isA<JsonContractException>()),
      );
    }
  });

  late QuizEngineBloc engine;
  late SocketHub hub;
  late int now;
  final peers = <Peer>[];
  final logs = <ServerLogEntry>[];

  Peer peer() {
    final value = Peer(hub);
    peers.add(value);
    return value;
  }

  setUp(() {
    now = 1000000000;
    logs.clear();
    engine = QuizEngineBloc(now: () => now);
    hub = SocketHub(
      engine: engine,
      serverName: 'Host',
      now: () => now,
      onLog: logs.add,
    );
  });
  tearDown(() async {
    await hub.close();
    for (final p in peers) {
      await p.input.close();
    }
    peers.clear();
    await engine.close();
  });

  test(
    'direct join and watch frames enforce the code before any snapshot',
    () async {
      engine.access.configure(code: 'secret-code');
      final player = peer();
      await player.send(const JoinRequest(name: 'Ada'));
      expect(player.error.code, 'codeRequired');
      await player.send(const JoinRequest(name: 'Ada', joinCode: 'wrong'));
      expect(player.error.code, 'invalidCode');
      expect(player.messages.whereType<GameSnapshotMessage>(), isEmpty);
      expect(engine.state.game.players, isEmpty);
      await player.send(
        const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
      );
      expect(player.accepted.playerId, isNotEmpty);

      final tv = peer();
      await tv.send(const WatchRequest());
      expect(tv.error.code, 'codeRequired');
      expect(tv.messages.whereType<GameSnapshotMessage>(), isEmpty);
      await tv.send(const WatchRequest(joinCode: 'secret-code'));
      expect(tv.messages.whereType<WatchAcceptedMessage>(), hasLength(1));
      expect(engine.state.game.players, hasLength(1));
    },
  );

  test(
    'pending players receive no game or identity and cannot use other actions',
    () async {
      engine.access.configure(requireApproval: true);
      final waiting = peer();
      await waiting.send(const JoinRequest(name: 'Ada', newTeamName: 'Owls'));
      expect(
        waiting.messages.whereType<AdmissionPendingMessage>(),
        hasLength(1),
      );
      expect(waiting.messages.whereType<JoinAcceptedMessage>(), isEmpty);
      expect(engine.state.game.players, isEmpty);
      expect(engine.state.game.teams, isEmpty);
      await waiting.send(
        SubmissionMessage(
          BuzzerPress(
            playerId: 'forged',
            questionId: 'q',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
          ),
        ),
      );
      expect(waiting.error.code, 'notJoined');
      await waiting.send(const WatchRequest());
      await waiting.send(const LobbyRequest());
      engine.add(const StartGameEvent());
      await pumpEventQueue();
      expect(waiting.messages.whereType<GameSnapshotMessage>(), isEmpty);
      expect(waiting.messages.whereType<WatchAcceptedMessage>(), isEmpty);
      final id = engine.access.state.requests.keys.single;
      engine.access.decide(id, approve: true);
      await pumpEventQueue();
      expect(engine.state.game.players, hasLength(1));
      expect(engine.state.game.teams.values.single.name, 'Owls');
      expect(waiting.messages.whereType<JoinAcceptedMessage>(), hasLength(1));
      expect(engine.access.state.requests, isEmpty);
    },
  );

  test(
    'rejection closes the request without creating players or teams',
    () async {
      engine.access.configure(requireApproval: true);
      final waiting = peer();
      await waiting.send(const JoinRequest(name: 'Ada', newTeamName: 'Owls'));
      engine.access.decide(
        engine.access.state.requests.keys.single,
        approve: false,
      );
      await pumpEventQueue();
      expect(waiting.error.code, 'admissionRejected');
      expect(waiting.closed, isTrue);
      expect(engine.access.state.requests, isEmpty);
      expect(engine.state.game.players, isEmpty);
      expect(engine.state.game.teams, isEmpty);
      await waiting.send(const JoinRequest(name: 'Replay'));
      expect(engine.state.game.players, isEmpty);
    },
  );

  test('locking rejects waiting/new joins; resume bypasses lock, code and approval', () async {
    final original = peer();
    await original.send(const JoinRequest(name: 'Ada'));
    final accepted = original.accepted;
    engine.access.configure(requireApproval: true, code: 'new-secret');
    final waiting = peer();
    await waiting.send(const JoinRequest(name: 'New', joinCode: 'new-secret'));
    engine.access.configure(locked: true);
    await pumpEventQueue();
    expect(waiting.error.code, 'lobbyLocked');
    final blocked = peer();
    await blocked.send(const JoinRequest(name: 'New'));
    expect(blocked.error.code, 'lobbyLocked');
    final returning = peer();
    await returning.send(
      JoinRequest(
        name: 'Ada',
        resumePlayerId: accepted.playerId,
        resumeToken: accepted.resumeToken,
      ),
    );
    expect(returning.accepted.playerId, accepted.playerId);
    expect(engine.state.game.players, hasLength(1));
    expect(original.closed, isTrue);
    await original.input.close();
    await pumpEventQueue();
    expect(engine.state.game.players[accepted.playerId]!.isConnected, isTrue);
    engine.access.configure(locked: false);
    await blocked.send(const JoinRequest(name: 'New', joinCode: 'new-secret'));
    expect(blocked.messages.whereType<AdmissionPendingMessage>(), hasLength(1));
  });

  test(
    'disconnect removes a pending approval and stale approval cannot admit it',
    () async {
      engine.access.configure(requireApproval: true);
      final waiting = peer();
      await waiting.send(const JoinRequest(name: 'Ada'));
      final id = engine.access.state.requests.keys.single;
      await waiting.send(const LeaveNotice());
      engine.access.decide(id, approve: true);
      await pumpEventQueue();
      expect(engine.access.state.requests, isEmpty);
      expect(engine.state.game.players, isEmpty);
    },
  );

  for (final ban in [false, true]) {
    test(
      '${ban ? "ban" : "remove"} revokes resume and read capabilities, including with failed persistence',
      () async {
        engine.access.configure(code: 'secret-code');
        final original = peer();
        await original.send(
          const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
        );
        final accepted = original.accepted;
        expect(engine.access.mayRead(accepted.accessToken), isTrue);
        engine.persistRecovery = () =>
            Future.error(StateError('storage unavailable'));
        engine.add(KickPlayerEvent(accepted.playerId, ban: ban));
        await pumpEventQueue();
        expect(original.closed, isTrue);
        expect(original.error.code, ban ? 'banned' : 'kicked');
        expect(engine.resumeTokenHashes, isEmpty);
        expect(engine.access.mayRead(accepted.accessToken), isFalse);
        engine.persistRecovery = null;
        final replay = peer();
        await replay.send(
          JoinRequest(
            name: 'Ada',
            resumePlayerId: accepted.playerId,
            resumeToken: accepted.resumeToken,
            joinCode: 'secret-code',
          ),
        );
        expect(replay.error.code, ban ? 'banned' : 'invalidResume');
        expect(engine.state.game.players, isEmpty);
        final tokenOnly = peer();
        await tokenOnly.send(
          JoinRequest(
            name: 'Ada',
            resumeToken: accepted.resumeToken,
            joinCode: 'secret-code',
          ),
        );
        expect(tokenOnly.error.code, 'invalidResume');
        final fresh = peer();
        await fresh.send(
          const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
        );
        expect(fresh.accepted.playerId, isNot(accepted.playerId));
      },
    );
  }

  test('bans and policy survive hub replacement and JSON recovery', () async {
    final original = peer();
    await original.send(const JoinRequest(name: 'Ada'));
    final accepted = original.accepted;
    engine.add(KickPlayerEvent(accepted.playerId, ban: true));
    await pumpEventQueue();
    engine.access.configure(
      code: 'secret-code',
      locked: true,
      requireApproval: true,
      allowSpectators: false,
    );
    final restored = SessionAccessState.fromJson(engine.access.state.toJson());
    expect(restored.bannedPlayerIds, {accepted.playerId});
    expect(restored.codeHash, SessionAccess.digestCredential('secret-code'));
    expect(restored.locked, isTrue);
    expect(restored.requireApproval, isTrue);
    expect(restored.allowSpectators, isFalse);
    expect(restored.toJson().toString(), isNot(contains('secret-code')));
    await hub.close();
    hub = SocketHub(engine: engine, serverName: 'Restarted', now: () => now);
    final replay = peer();
    await replay.send(
      JoinRequest(
        name: 'Ada',
        resumePlayerId: accepted.playerId,
        resumeToken: accepted.resumeToken,
      ),
    );
    expect(replay.error.code, 'banned');
  });

  test('spectators bypass player lock/approval, but not their switch or code changes', () async {
    engine.access.configure(
      locked: true,
      requireApproval: true,
      code: 'secret-code',
    );
    final tv = peer();
    await tv.send(const WatchRequest(joinCode: 'secret-code'));
    final credential = tv.messages
        .whereType<WatchAcceptedMessage>()
        .single
        .accessToken;
    expect(engine.access.mayRead(credential), isTrue);
    expect(engine.access.state.requests, isEmpty);
    await tv.send(const JoinRequest(name: 'Impostor', joinCode: 'secret-code'));
    expect(tv.error.code, 'alreadyJoined');
    engine.access.configure(allowSpectators: false);
    await pumpEventQueue();
    expect(tv.closed, isTrue);
    expect(engine.access.mayRead(credential), isFalse);
    final denied = peer();
    await denied.send(const WatchRequest(joinCode: 'secret-code'));
    expect(denied.error.code, 'spectatorsDisabled');
    engine.access.configure(allowSpectators: true);
    final second = peer();
    await second.send(const WatchRequest(joinCode: 'secret-code'));
    engine.access.configure(code: 'changed-code');
    await pumpEventQueue();
    expect(second.closed, isTrue);
    final third = peer();
    await third.send(const WatchRequest(joinCode: 'secret-code'));
    expect(third.error.code, 'invalidCode');
    expect(engine.state.game.players, isEmpty);
  });

  test(
    'five guesses per socket and ten per minute across reconnects and roles',
    () async {
      engine.access.configure(code: 'secret-code');
      final first = peer();
      for (var i = 0; i < 5; i++) {
        await first.send(const JoinRequest(name: 'Guess', joinCode: 'wrong'));
        expect(first.error.code, 'invalidCode');
      }
      await first.send(
        const JoinRequest(name: 'Guess', joinCode: 'secret-code'),
      );
      expect(first.error.code, 'codeRateLimited');
      for (var i = 0; i < 5; i++) {
        final reconnect = peer();
        await reconnect.send(const WatchRequest(joinCode: 'wrong'));
        expect(reconnect.error.code, 'invalidCode');
      }
      final blocked = peer();
      await blocked.send(
        const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
      );
      expect(blocked.error.code, 'codeRateLimited');
      now += const Duration(minutes: 1).inMicroseconds - 1;
      await blocked.send(
        const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
      );
      expect(blocked.messages.whereType<JoinAcceptedMessage>(), isEmpty);
      now++;
      final allowed = peer();
      await allowed.send(
        const JoinRequest(name: 'Ada', joinCode: 'secret-code'),
      );
      expect(allowed.messages.whereType<JoinAcceptedMessage>(), hasLength(1));
    },
  );

  test('code changes while waiting are checked again at approval', () async {
    engine.access.configure(code: 'secret-code', requireApproval: true);
    final waiting = peer();
    await waiting.send(const JoinRequest(name: 'Ada', joinCode: 'secret-code'));
    engine.access.configure(code: 'new-secret');
    engine.access.decide(
      engine.access.state.requests.keys.single,
      approve: true,
    );
    await pumpEventQueue();
    expect(waiting.error.code, 'invalidCode');
    expect(engine.state.game.players, isEmpty);
    await waiting.send(
      const JoinRequest(name: 'Changed identity', joinCode: 'new-secret'),
    );
    expect(waiting.messages.whereType<JoinAcceptedMessage>(), isEmpty);
    expect(engine.access.state.requests.values.single.name, 'Changed identity');
  });

  test(
    'diagnostics never echo codes, names, resume tokens or transport errors',
    () async {
      const secret = 'private-secret';
      engine.access.configure(code: secret);
      final original = peer();
      await original.send(const JoinRequest(name: secret, joinCode: secret));
      final token = original.accepted.resumeToken!;
      original.input.addError(
        StateError('$secret $token https://host/rooms/private'),
      );
      await pumpEventQueue();
      final diagnostic = logs.map((entry) => entry.message).join('\n');
      expect(diagnostic, isNot(contains(secret)));
      expect(diagnostic, isNot(contains(token)));
      expect(diagnostic, isNot(contains('https://host/rooms/private')));
    },
  );

  test(
    'real client waits beyond join timeout, then completes on host approval',
    () async {
      engine.access.configure(code: 'secret-code', requireApproval: true);
      final server = EmbeddedServer(engine: engine);
      final host = (await server.start(port: 0)).loopbackUri;
      final client = QuizClient(baseUri: host);
      addTearDown(() async {
        await client.dispose();
        await server.dispose();
      });
      final pending = client.admissions.firstWhere((waiting) => waiting);
      final joining = client.connect(
        name: 'Ada',
        joinCode: 'secret-code',
        handshakeProbes: 1,
        joinTimeout: const Duration(milliseconds: 100),
      );
      await pending;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(client.playerId, isNull);
      engine.access.decide(
        engine.access.state.requests.keys.single,
        approve: true,
      );
      await joining;
      expect(client.playerId, isNotNull);
    },
  );

  test('protected HTTP snapshots and media require a live admitted read capability', () async {
    engine.access.configure(code: 'secret-code');
    final server = EmbeddedServer(engine: engine);
    final host = (await server.start(port: 0)).loopbackUri;
    final client = QuizClient(baseUri: host);
    addTearDown(() async {
      await client.dispose();
      await server.dispose();
    });
    final stateUri = host.resolve('/api/state');
    expect((await http.get(stateUri)).statusCode, 403);
    expect(
      (await http.get(host.resolve('/api/media/${'a' * 64}'))).statusCode,
      403,
    );
    await client.connect(
      name: 'Ada',
      joinCode: 'secret-code',
      handshakeProbes: 1,
    );
    final token = client.mediaBaseUri.queryParameters['access']!;
    expect(
      (await http.get(
        stateUri,
        headers: {'authorization': 'Bearer $token'},
      )).statusCode,
      200,
    );
    await client.disconnect();
    expect(
      (await http.get(
        stateUri,
        headers: {'authorization': 'Bearer $token'},
      )).statusCode,
      403,
    );
  });
}
