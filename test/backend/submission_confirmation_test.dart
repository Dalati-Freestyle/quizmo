import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/protocol/messages.dart';
import 'package:quizmo/core/sync/clock.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/player_session_store.dart';

class _MemoryStore extends PlayerSessionStore {
  SavedPlayerSession? saved;
  @override
  Future<SavedPlayerSession?> read() async => saved;
  @override
  Future<void> save(SavedPlayerSession value) async => saved = value;
  @override
  Future<void> clear() async => saved = null;
}

void main() {
  late QuizEngineBloc engine;
  late SocketHub hub;
  late HttpServer server;
  late QuizClient client;
  late PlayerSessionCubit session;
  final sockets = <WebSocket>[];
  WebSocket? suppressConfirmationsOn;
  var suppressSubmission = false;
  var clockShift = 0;

  Future<void> waitForGame(bool Function(GameState) predicate) async {
    if (predicate(engine.state.game)) return;
    await engine.stream
        .firstWhere((state) => predicate(state.game))
        .timeout(const Duration(seconds: 5));
  }

  Future<PlayerSessionState> waitForSession(
    bool Function(PlayerSessionState) predicate,
  ) async {
    if (predicate(session.state)) return session.state;
    return session.stream
        .firstWhere(predicate)
        .timeout(const Duration(seconds: 12));
  }

  void answer() => session.submit(
    (id, timestamp, offset) => TrueFalseAnswer(
      playerId: id,
      questionId: 'q',
      clientTimestampMicros: timestamp,
      clockOffsetMicros: offset,
      value: true,
    ),
  );

  setUp(() async {
    sockets.clear();
    suppressConfirmationsOn = null;
    suppressSubmission = false;
    clockShift = 0;
    engine = QuizEngineBloc(
      questionBank: const [
        TrueFalseQuestion(
          id: 'q',
          prompt: 'True?',
          correctAnswer: true,
          timeLimit: Duration(minutes: 2),
          scoringRule: FixedPointsRule(correctPoints: 10),
        ),
      ],
    );
    engine.add(const PlayerJoinedEvent(Player(id: 'other', name: 'Other')));
    hub = SocketHub(engine: engine, serverName: 'Test host');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        hub.attach(
          stream: socket.where((frame) {
            return !(suppressSubmission &&
                frame is String &&
                ClientMessage.decode(frame) is SubmissionMessage);
          }),
          send: (frame) {
            if (socket == suppressConfirmationsOn &&
                ServerMessage.decode(frame) is GameSnapshotMessage) {
              return;
            }
            socket.add(frame);
          },
          close: () async {
            await socket.close();
          },
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
    final host = Uri.parse('http://127.0.0.1:${server.port}');
    client = QuizClient(
      baseUri: host,
      now: () => systemNowMicros() + clockShift,
      resyncInterval: const Duration(hours: 1),
    );
    session = PlayerSessionCubit(
      store: _MemoryStore(),
      createClient: (_) => client,
    );
    await session.connect(baseUri: host, name: 'Ada');
    await waitForSession((state) => state.game != null && state.isConnected);
    engine.add(const StartRoundEvent('q'));
    await waitForSession((state) => state.roundStatus.acceptsInput);
  });

  tearDown(() async {
    await session.close();
    await hub.close();
    await server.close(force: true);
    await engine.close();
  });

  test('acceptance is not announced before persistence completes', () async {
    final committed = Completer<void>();
    engine.persistRecovery = () => committed.future;
    answer();
    await waitForGame((game) => game.round.answers.isNotEmpty);
    expect(session.state.submissionStatus, SubmissionStatus.sending);
    committed.complete();
    await waitForSession(
      (state) => state.submissionStatus == SubmissionStatus.accepted,
    );
  });

  test('lost confirmation is uncertain until rejoin restores authoritative acceptance', () async {
    final states = <PlayerSessionState>[];
    final subscription = session.stream.listen(states.add);
    addTearDown(subscription.cancel);
    final id = session.state.playerId!;
    suppressConfirmationsOn = sockets.single;
    answer();
    expect(session.state.submissionStatus, SubmissionStatus.sending);
    await waitForGame((game) => game.round.answers.containsKey(id));
    expect(session.state.submissionStatus, isNot(SubmissionStatus.accepted));
    await waitForSession(
      (state) => state.submissionStatus == SubmissionStatus.accepted,
    );
    expect(
      states.any(
        (state) => state.submissionStatus == SubmissionStatus.uncertain,
      ),
      isTrue,
    );
    expect(
      states.any((state) => state.status == QuizClientStatus.reconnecting),
      isTrue,
    );
    expect(session.state.playerId, id);
    expect(engine.state.game.players, hasLength(2));
    final accepted = engine.state.game.round.answers[id]!;
    client.submitAnswer((_, _, _) => accepted);
    client.submitAnswer((_, _, _) => accepted);
    await pumpEventQueue();
    expect(engine.state.game.round.answers, {id: accepted});
    engine.add(const RevealRoundEvent());
    await waitForGame((game) => game.round.status == RoundStatus.revealed);
    expect(engine.state.game.scores.scoreOf(id), 10);
    client.submitAnswer((_, _, _) => accepted);
    await pumpEventQueue();
    expect(engine.state.game.scores.scoreOf(id), 10);
  });

  test(
    'lost submission is not replayed; a fresh snapshot unlocks a manual retry',
    () async {
      suppressSubmission = true;
      answer();
      await waitForSession(
        (state) =>
            state.isConnected &&
            state.submissionStatus == SubmissionStatus.rejected,
      );
      expect(session.state.lastSubmittedOptionId, isNull);
      expect(engine.state.game.round.answers, isEmpty);
      suppressSubmission = false;
      answer();
      await waitForSession(
        (state) => state.submissionStatus == SubmissionStatus.accepted,
      );
      expect(engine.state.game.round.answers, hasLength(1));
    },
  );

  test('resume after a long device lock checks the stale socket and resynchronizes the clock', () async {
    final id = session.state.playerId;
    clockShift = const Duration(minutes: 1).inMicroseconds;
    session.resume();
    await waitForSession(
      (state) => state.status == QuizClientStatus.reconnecting,
    );
    await waitForSession((state) => state.isConnected);
    expect(session.state.playerId, id);
    expect(client.clock.clockOffsetMicros, closeTo(clockShift, 100000));
    answer();
    await waitForSession(
      (state) => state.submissionStatus == SubmissionStatus.accepted,
    );
  });

  test(
    'a late answer is never accepted after the host closes the round',
    () async {
      final id = session.state.playerId!;
      final answer = TrueFalseAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: systemNowMicros(),
        clockOffsetMicros: 0,
        value: true,
      );
      engine.add(const EndRoundEvent());
      await waitForGame((game) => !game.round.status.acceptsInput);
      client.submitAnswer((_, _, _) => answer);
      await pumpEventQueue();
      expect(engine.state.game.round.answers, isEmpty);
      expect(engine.state.game.scores.scoreOf(id), 0);
    },
  );

  test(
    'an explicitly ended host room is terminal and does not reconnect',
    () async {
      await hub.close();
      await waitForSession((state) => state.status == QuizClientStatus.closed);
      expect(session.state.error, contains('closed this room'));
      session.resume();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(sockets, hasLength(1));
      expect(session.state.status, QuizClientStatus.closed);
    },
  );
}
