import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/handlers/socket_handlers.dart';
import 'package:quizmo/core/engine/guest_wifi_cubit.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/protocol/messages.dart';

class _Peer {
  _Peer(SocketHub hub) {
    hub.attach(
      stream: input.stream,
      send: (frame) => messages.add(ServerMessage.decode(frame)),
      close: () async {},
    );
  }
  final input = StreamController<dynamic>();
  final messages = <ServerMessage>[];
  Future<void> send(ClientMessage message) async {
    input.add(message.encode());
    await pumpEventQueue();
  }

  List<GuestWifi?> get wifi => [
    for (final message in messages.whereType<GuestWifiMessage>()) message.wifi,
  ];
}

void main() {
  const home = GuestWifi(ssid: 'Quiz Night', password: 'secret-pass');
  late QuizEngineBloc engine;
  late GuestWifiCubit guestWifi;
  final peers = <_Peer>[];

  setUp(() {
    engine = QuizEngineBloc();
    guestWifi = GuestWifiCubit();
  });
  tearDown(() async {
    for (final peer in peers) {
      await peer.input.close();
    }
    peers.clear();
    await guestWifi.close();
    await engine.close();
  });

  _Peer peer(SocketHub hub) {
    final value = _Peer(hub);
    peers.add(value);
    return value;
  }

  test('TV screens receive the guest Wi-Fi, players never do', () async {
    guestWifi.publish(home);
    final hub = SocketHub(
      engine: engine,
      serverName: 'Host',
      guestWifi: guestWifi,
    );
    final tv = peer(hub);
    final player = peer(hub);
    await tv.send(const WatchRequest());
    await player.send(const JoinRequest(name: 'Ada'));
    expect(tv.wifi, [home]);

    guestWifi.publish(null);
    await pumpEventQueue();
    const other = GuestWifi(ssid: 'Other', security: WifiSecurity.open);
    guestWifi.publish(other);
    await pumpEventQueue();
    expect(tv.wifi, [home, null, other]);
    expect(player.messages.whereType<GuestWifiMessage>(), isEmpty);
    await hub.close();
  });

  test(
    'a hub without guest Wi-Fi (internet relay) never announces one',
    () async {
      final hub = SocketHub(engine: engine, serverName: 'Relay');
      final tv = peer(hub);
      await tv.send(const WatchRequest());
      expect(tv.messages.whereType<WatchAcceptedMessage>(), hasLength(1));
      expect(tv.messages.whereType<GuestWifiMessage>(), isEmpty);
      await hub.close();
    },
  );

  test('an invalid network is never published', () {
    guestWifi.publish(const GuestWifi(ssid: 'Net', password: 'short'));
    expect(guestWifi.state, isNull);
  });

  test('the announcement survives the wire format', () {
    for (final message in [
      const GuestWifiMessage(home),
      const GuestWifiMessage(null),
    ]) {
      expect(ServerMessage.decode(message.encode()), message);
    }
  });
}
