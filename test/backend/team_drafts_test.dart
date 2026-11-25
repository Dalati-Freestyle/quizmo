/// Live drafts over real sockets: only team mates receive them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/sync/clock.dart';

void main() {
  late QuizEngineBloc engine;
  late SocketHub hub;
  late HttpServer server;
  final clients = <QuizClient>[];
  final received = <String, List<String>>{};
  final logs = <String>[];

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue);
  }

  Future<QuizClient> join(String name, {String? team}) async {
    final uri = Uri.parse('http://127.0.0.1:${server.port}');
    final client = QuizClient(
      baseUri: uri,
      resyncInterval: const Duration(hours: 1),
    );
    clients.add(client);
    final frames = received[name] = [];
    client.teamDrafts.listen((message) => frames.add(message.encode()));
    client.snapshots.listen((message) => frames.add(message.encode()));
    if (team == null) {
      await client.watch();
    } else {
      await client.connect(name: name, teamId: team, handshakeProbes: 1);
    }
    return client;
  }

  Future<void> start({SnowflakeScoring? snowflake}) async {
    engine = QuizEngineBloc(
      questionBank: const [
        OrderingQuestion(
          id: 'q',
          prompt: 'Order?',
          items: [
            AnswerOption(id: 'x', label: 'X'),
            AnswerOption(id: 'y', label: 'Y'),
          ],
          correctOrder: ['x', 'y'],
          timeLimit: Duration.zero,
        ),
      ],
      teams: const {
        'a': Team(id: 'a', name: 'A'),
        'b': Team(id: 'b', name: 'B'),
      },
      mode: const TeamMode(),
      snowflakeScoring: snowflake,
    );
    hub = SocketHub(
      engine: engine,
      serverName: 'Test host',
      onLog: (entry) => logs.add(entry.message),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        hub.attach(
          stream: socket,
          send: socket.add,
          close: () async => socket.close(),
        );
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'clientSentAtMicros': body['clientSentAtMicros'],
            'hostTimeMicros': systemNowMicros(),
          }),
        );
        await request.response.close();
      }
    });
  }

  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    received.clear();
    logs.clear();
    await hub.close();
    await server.close(force: true);
    await engine.close();
  });

  void draft(QuizClient client, List<String> order) => client.sendDraft(
    questionId: 'q',
    roundStartedAt: engine.state.game.round.startedAtHostMicros!,
    changedAtMicros: systemNowMicros(),
    content: OrderingAnswer(
      // The sender is decided by the connection, not by the message.
      playerId: 'somebody-else',
      questionId: 'q',
      clientTimestampMicros: 0,
      clockOffsetMicros: 0,
      itemIds: order,
    ),
  );

  bool sees(String name, String text) =>
      received[name]!.any((frame) => frame.contains(text));

  test('drafts reach the own team only, also after joining late', () async {
    await start();
    final ada = await join('ada', team: 'a');
    await join('linus', team: 'a');
    await join('other', team: 'b');
    await join('tv');
    engine.add(const StartRoundEvent('q'));
    await until(() => sees('linus', 'Order?') && sees('ada', 'Order?'));
    final before = engine.state;
    draft(ada, ['y', 'x']);
    await until(() => sees('linus', '"itemIds":["y","x"]'));
    expect(identical(engine.state, before), isTrue);
    expect(engine.draftOf(ada.playerId!), isNotNull);
    expect(sees('other', 'itemIds'), isFalse);
    expect(sees('tv', 'itemIds'), isFalse);
    expect(logs.join(), isNot(contains('itemIds')));

    // Somebody who joins later gets the current state with the snapshot.
    await join('late', team: 'a');
    await until(() => sees('late', '"itemIds":["y","x"]'));

    // After a team change nothing of the old team arrives any more.
    final late = clients.last;
    engine.add(AssignTeamEvent(playerId: late.playerId!, teamId: 'b'));
    await until(() => engine.state.game.players[late.playerId]!.teamId == 'b');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    received['late']!.clear();
    draft(ada, ['x', 'y']);
    await until(() => sees('linus', '"itemIds":["x","y"]'));
    expect(sees('late', 'itemIds'), isFalse);
  });

  test('fast typing is bundled and the last state always arrives', () async {
    await start();
    final ada = await join('ada', team: 'a');
    await join('linus', team: 'a');
    engine.add(const StartRoundEvent('q'));
    await until(() => sees('linus', 'Order?') && sees('ada', 'Order?'));
    received['linus']!.clear();
    for (var i = 0; i < 9; i++) {
      draft(ada, i.isEven ? ['x', 'y'] : ['y', 'x']);
    }
    draft(ada, ['y', 'x']);
    await until(() => sees('linus', '"itemIds":["y","x"]'));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(received['linus']!.length, lessThan(5));
    expect(received['linus']!.last, contains('"itemIds":["y","x"]'));
  });

  test('snowflake shares nothing', () async {
    await start(snowflake: SnowflakeScoring.winnerOnly);
    final ada = await join('ada', team: 'a');
    await join('linus', team: 'a');
    engine.add(const StartRoundEvent('q'));
    await until(() => sees('linus', 'Order?') && sees('ada', 'Order?'));
    draft(ada, ['y', 'x']);
    await until(() => engine.draftOf(ada.playerId!) != null);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(sees('linus', 'itemIds'), isFalse);
  });
}
