import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/protocol/messages.dart';

void main() {
  test('a silent joined socket becomes disconnected without claiming the room ended', () async {
    var now = 1000000;
    var socketClosed = false;
    final engine = QuizEngineBloc(now: () => now);
    final hub = SocketHub(engine: engine, serverName: 'Host', now: () => now);
    final inbound = StreamController<String>();
    final frames = <ServerMessage>[];
    hub.attach(
      stream: inbound.stream,
      send: (frame) => frames.add(ServerMessage.decode(frame)),
      close: () async {
        socketClosed = true;
      },
    );
    inbound.add(const JoinRequest(name: 'Ada').encode());
    await engine.stream
        .firstWhere((state) => state.game.connectedPlayers.length == 1)
        .timeout(const Duration(seconds: 5));
    expect(engine.state.game.connectedPlayers, hasLength(1));
    now += const Duration(seconds: 40).inMicroseconds;
    await engine.stream
        .firstWhere((state) => state.game.connectedPlayers.isEmpty)
        .timeout(const Duration(seconds: 12));
    expect(socketClosed, isTrue);
    expect(engine.state.game.connectedPlayers, isEmpty);
    expect(engine.state.game.players, hasLength(1));
    expect(
      frames.whereType<ProtocolErrorMessage>().where(
        (frame) => frame.code == 'hostClosed',
      ),
      isEmpty,
    );
    await inbound.close();
    await hub.close();
    await engine.close();
  });
}
