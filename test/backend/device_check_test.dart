import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/protocol/messages.dart';

void main() {
  test(
    'the device check reaches players, records taps and never touches the game',
    () async {
      final engine = QuizEngineBloc(now: () => 1000000);
      final hub = SocketHub(
        engine: engine,
        serverName: 'Host',
        now: () => 1000000,
      );
      final inbound = StreamController<String>();
      final frames = <ServerMessage>[];
      hub.attach(
        stream: inbound.stream,
        send: (frame) => frames.add(ServerMessage.decode(frame)),
        close: () async {},
      );
      inbound.add(const JoinRequest(name: 'Ada').encode());
      await engine.stream
          .firstWhere((state) => state.game.connectedPlayers.length == 1)
          .timeout(const Duration(seconds: 5));
      await pumpEventQueue();
      final gameBefore = engine.state.game;
      final playerId = gameBefore.players.keys.single;

      final check = hub.startDeviceCheck();
      final request = frames.whereType<DeviceCheckMessage>().single;
      expect(request.checkId, check.id);

      // A stale id is ignored, the right one is recorded.
      inbound.add(const DeviceCheckReply('stale').encode());
      await pumpEventQueue();
      expect(hub.deviceCheck!.confirmedPlayerIds, isEmpty);
      inbound.add(DeviceCheckReply(check.id).encode());
      await pumpEventQueue();
      expect(hub.deviceCheck!.confirmedPlayerIds, {playerId});
      expect(engine.state.game, gameBefore);

      hub.stopDeviceCheck();
      expect(hub.deviceCheck, isNull);
      expect(frames.whereType<DeviceCheckMessage>().last.checkId, isNull);

      await inbound.close();
      await hub.close();
      await engine.close();
    },
  );

  test('the messages survive the wire format', () {
    expect(
      ServerMessage.decode(const DeviceCheckMessage('c1').encode()),
      const DeviceCheckMessage('c1'),
    );
    expect(
      ServerMessage.decode(const DeviceCheckMessage(null).encode()),
      const DeviceCheckMessage(null),
    );
    expect(
      ClientMessage.decode(const DeviceCheckReply('c1').encode()),
      const DeviceCheckReply('c1'),
    );
  });
}
