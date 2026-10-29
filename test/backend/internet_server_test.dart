@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quizmo/backend/internet_server.dart';
import 'package:quizmo/backend/relay_host.dart';
import 'package:quizmo/backend/web_client_bundle.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/net/session_uri.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  const allowedOrigin = 'https://quiz.example.com';
  late InternetServer server;
  late Uri base;
  final hosts = <RelayHost>[];
  final engines = <QuizEngineBloc>[];
  final clients = <QuizClient>[];
  final sockets = <IOWebSocketChannel>[];

  Future<RelayHost> host() async {
    final engine = QuizEngineBloc(
      questionBank: sampleQuestionBank,
      teams: sampleTeams,
    );
    engines.add(engine);
    final host = RelayHost(
      engine: engine,
      origin: base,
      connect: (uri) =>
          IOWebSocketChannel.connect(uri, headers: {'Origin': allowedOrigin}),
    );
    hosts.add(host);
    await host.start();
    return host;
  }

  QuizClient client(Uri room) {
    final client = QuizClient(baseUri: room);
    clients.add(client);
    return client;
  }

  setUp(() async {
    server = InternetServer(
      publicOrigin: Uri.parse(allowedOrigin),
      maxRooms: 2,
      webClient: InMemoryWebClientBundle({
        'index.html': Uint8List.fromList(utf8.encode('<html>quizmo</html>')),
      }),
    );
    final port = await server.start(port: 0);
    base = Uri.parse('http://127.0.0.1:$port');
  });
  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    for (final socket in sockets) {
      await socket.sink.close();
    }
    for (final host in hosts) {
      await host.dispose();
    }
    for (final engine in engines) {
      await engine.close();
    }
    await server.close();
    clients.clear();
    hosts.clear();
    engines.clear();
    sockets.clear();
  });

  test(
    'same-origin health, security headers, deep links and origin rejection',
    () async {
      final health = await http.get(base.resolve('/api/health'));
      expect(health.statusCode, 200);
      expect(health.headers['x-content-type-options'], 'nosniff');
      expect(health.headers['referrer-policy'], 'no-referrer');
      final tv = await http.get(base.resolve('/rooms/invitation/tv'));
      expect(tv.body, '<html>quizmo</html>');
      expect(tv.headers['cache-control'], 'no-store');
      expect((await http.get(base.resolve('/relay/host'))).statusCode, 403);
      expect(
        (await http.get(
          base.resolve('/api/health'),
          headers: {'Origin': 'https://evil.example'},
        )).statusCode,
        403,
      );
      expect((await http.post(base.resolve('/rooms/a'))).statusCode, 405);
      expect(
        (await http.get(base.resolve('/rooms/missing/ws'))).statusCode,
        404,
      );
    },
  );

  test(
    'browser hosting supports lobby, clock handshake, player, TV and redaction',
    () async {
      final room = await host();
      final player = client(room.endpoint!.publicUri!);
      final tv = client(room.endpoint!.publicUri!);
      await player.browseLobby();
      expect(engines.single.state.game.players, isEmpty);
      await player.connect(name: 'Ada', teamId: 'team-red', handshakeProbes: 3);
      await tv.watch();
      expect(player.clock.isSynced, isTrue);
      expect(tv.playerId, isNull);
      final playerSnapshot = player.games.firstWhere(
        (game) => game.round.question?.id == 'q-capital',
      );
      final tvSnapshot = tv.games.firstWhere(
        (game) => game.round.question?.id == 'q-capital',
      );
      engines.single.add(const StartRoundEvent('q-capital'));
      for (final game in await Future.wait([
        playerSnapshot,
        tvSnapshot,
      ]).timeout(const Duration(seconds: 5))) {
        expect(
          (game.round.question as MultipleChoiceQuestion).correctOptionId,
          isNull,
        );
        expect(game.players, hasLength(1));
      }
      final answered = engines.single.stream.firstWhere(
        (state) => state.game.round.answers.containsKey(player.playerId),
      );
      player.submitChoice(questionId: 'q-capital', optionId: 'b');
      await answered.timeout(const Duration(seconds: 5));
      expect(
        room.endpoint!.lanTvUri.path,
        '${room.endpoint!.publicUri!.path}/tv',
      );
    },
  );

  test('rooms have unpredictable invitations and isolated state', () async {
    final first = await host();
    final second = await host();
    expect(first.endpoint!.publicUri, isNot(second.endpoint!.publicUri));
    expect(first.endpoint!.publicUri!.pathSegments.last, hasLength(32));
    final ada = client(first.endpoint!.publicUri!);
    final linus = client(second.endpoint!.publicUri!);
    await ada.connect(name: 'Ada', handshakeProbes: 1);
    await linus.connect(name: 'Linus', handshakeProbes: 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engines.first.state.game.players.values.single.name, 'Ada');
    expect(engines.last.state.game.players.values.single.name, 'Linus');
    expect(server.roomCount, 2);
    final overflow = IOWebSocketChannel.connect(
      base.resolve('/relay/host').replace(scheme: 'ws'),
      headers: {'Origin': allowedOrigin},
    );
    sockets.add(overflow);
    await expectLater(overflow.ready, throwsA(isA<Exception>()));
    await overflow.stream.drain<dynamic>().catchError((Object _) {});
  });

  test(
    'relay guests obey code, approval, lobby lock, resume and spectator policy',
    () async {
      final room = await host();
      final engine = engines.single;
      engine.access.configure(code: 'secret-code', requireApproval: true);
      final player = client(room.endpoint!.publicUri!);
      await expectLater(
        player.connect(name: 'Ada', joinCode: 'wrong', handshakeProbes: 1),
        throwsA(isA<JoinRejectedException>()),
      );
      final pending = player.admissions.firstWhere((value) => value);
      final joining = player.connect(
        name: 'Ada',
        joinCode: 'secret-code',
        handshakeProbes: 1,
      );
      await pending;
      expect(engine.state.game.players, isEmpty);
      engine.access.decide(
        engine.access.state.requests.keys.single,
        approve: true,
      );
      await joining;
      final id = player.playerId!;
      final token = player.resumeToken!;
      engine.access.configure(locked: true);
      final returning = client(room.endpoint!.publicUri!);
      await returning.connect(
        name: 'Ada',
        resumePlayerId: id,
        resumeToken: token,
        handshakeProbes: 1,
      );
      expect(returning.playerId, id);
      final tv = client(room.endpoint!.publicUri!);
      await tv.watch(joinCode: 'secret-code');
      engine.access.configure(allowSpectators: false);
      final disabled = client(room.endpoint!.publicUri!);
      await expectLater(
        disabled.watch(joinCode: 'secret-code'),
        throwsStateError,
      );
      engine.add(KickPlayerEvent(id, ban: true));
      await engine.stream.firstWhere((s) => !s.game.players.containsKey(id));
      await expectLater(
        returning.connect(
          name: 'Ada',
          resumePlayerId: id,
          resumeToken: token,
          handshakeProbes: 1,
        ),
        throwsStateError,
      );
    },
  );

  test('guest control envelopes cannot impersonate the host', () async {
    final room = await host();
    final guest = IOWebSocketChannel.connect(
      sessionSocketUri(room.endpoint!.publicUri!),
    );
    sockets.add(guest);
    await guest.ready;
    final messages = <String>[];
    final subscription = guest.stream.listen(
      (dynamic frame) => messages.add(frame as String),
    );
    guest.sink.add(jsonEncode({'type': 'frame', 'id': '0', 'data': 'stolen'}));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(messages.any((frame) => frame.contains('badRequest')), isTrue);
    expect(engines.single.state.game.players, isEmpty);
    expect(server.roomCount, 1);
    await subscription.cancel();
  });

  test('oversized guest messages are closed and the room survives', () async {
    final room = await host();
    final guest = IOWebSocketChannel.connect(
      sessionSocketUri(room.endpoint!.publicUri!),
    );
    sockets.add(guest);
    await guest.ready;
    final done = guest.stream.drain<dynamic>();
    guest.sink.add('x' * 65537);
    await done.timeout(const Duration(seconds: 5));
    expect(guest.closeCode, 3008);
    expect(server.roomCount, 1);
    await client(room.endpoint!.publicUri!)
        .connect(name: 'Ada', handshakeProbes: 1);
  });

  test(
    'closing the host removes its room and disconnects spectators',
    () async {
      final room = await host();
      final uri = room.endpoint!.publicUri!;
      final tv = client(uri);
      await tv.watch();
      final disconnected = tv.statuses.firstWhere(
        (status) => status == QuizClientStatus.closed,
      );
      await room.stop();
      await disconnected.timeout(const Duration(seconds: 5));
      await Stream.periodic(const Duration(milliseconds: 10))
          .firstWhere((_) => server.roomCount == 0)
          .timeout(const Duration(seconds: 5));
      expect(server.roomCount, 0);
      final returning = client(uri);
      await expectLater(
        returning.connect(name: 'Returning', handshakeProbes: 1),
        throwsA(
          isA<JoinRejectedException>().having(
            (error) => error.code,
            'code',
            'hostClosed',
          ),
        ),
      );
      expect(returning.status, QuizClientStatus.closed);
      expect(
        (await http.get(uri.replace(path: '${uri.path}/ws'))).statusCode,
        404,
      );
    },
  );

  test(
    'roster limit blocks join churn but existing players can resume',
    () async {
      final room = await host();
      final engine = engines.single;
      for (var i = 0; i < 255; i++) {
        engine.add(
          PlayerJoinedEvent(Player(id: 'seed-$i', name: 'Offline $i')),
        );
      }
      await engine.stream.firstWhere(
        (state) => state.game.players.length == 255,
      );
      final ada = client(room.endpoint!.publicUri!);
      await ada.connect(name: 'Ada', handshakeProbes: 1);
      final id = ada.playerId;
      final token = ada.resumeToken;
      final overflow = client(room.endpoint!.publicUri!);
      await expectLater(
        overflow.connect(name: 'Overflow', handshakeProbes: 1),
        throwsStateError,
      );
      expect(engine.state.game.players, hasLength(256));
      await ada.disconnect();
      await ada.connect(
        name: 'Ada',
        resumePlayerId: id,
        resumeToken: token,
        handshakeProbes: 1,
      );
      expect(ada.playerId, id);
      expect(engine.state.game.players, hasLength(256));
    },
  );
}
