import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/net/lan_discovery.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/quizmaster/host_server_cubit.dart';

import '../helpers/fake_lan_discovery.dart';

void main() {
  test(
    'host stop and close cannot race a pending start into advertising',
    () async {
      final backend = FakeBackend();
      final engine = QuizEngineBloc();
      final host = HostServerCubit(
        engine: engine,
        discovery: LanDiscoveryCubit(backend: backend),
      );
      final starting = host.start(port: 0);
      final stopping = host.stop();
      await Future.wait([starting, stopping]);
      expect(host.state.status, HostServerStatus.stopped);
      expect(backend.registrations.every((entry) => entry.closed), isTrue);
      final restarting = host.start(port: 0);
      final closing = host.close();
      await Future.wait([restarting, closing]);
      expect(host.isClosed, isTrue);
      expect(backend.registrations.every((entry) => entry.closed), isTrue);
      await engine.close();
      await backend.close();
    },
  );

  test(
    'health probe requires a valid health response, not just HTTP 200',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final uri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      var body = '<html>Not Quizmo</html>';
      var status = 200;
      server.listen((request) async {
        expect(request.uri.path, '/api/health');
        request.response.statusCode = status;
        request.response.write(body);
        await request.response.close();
      });
      expect(await probeLanHost(uri), isFalse);
      body = jsonEncode({
        'status': 'ok',
        'serverName': 'Quizmo',
        'hostTimeMicros': 1,
        'players': 0,
      });
      expect(await probeLanHost(uri), isTrue);
      status = 503;
      expect(await probeLanHost(uri), isFalse);
      await server.close(force: true);
      expect(await probeLanHost(uri), isFalse);
    },
  );

  test(
    'host publishes bound endpoint and accepts a discovered join URI',
    () async {
      final backend = FakeBackend();
      final discovery = LanDiscoveryCubit(backend: backend);
      final engine = QuizEngineBloc(recoverySessionId: 'private-session-id');
      final host = HostServerCubit(
        engine: engine,
        serverName: 'Living room',
        discovery: discovery,
      );
      addTearDown(() async {
        await host.close();
        await engine.close();
        await backend.close();
      });
      await host.start(port: 0);
      expect(host.state.status, HostServerStatus.running);
      final endpoint = host.state.endpoint!;
      expect(backend.publications.single, (
        name: 'Living room',
        port: endpoint.port,
      ));
      final uri = Uri(scheme: 'http', host: '127.0.0.1', port: endpoint.port);
      expect(await probeLanHost(uri), isTrue);
      final client = QuizClient(baseUri: uri);
      addTearDown(client.dispose);
      await client.connect(name: 'Guest', handshakeProbes: 1);
      expect(client.status, QuizClientStatus.connected);
      await client.dispose();
      await host.stop();
      expect(backend.registrations.every((entry) => entry.closed), isTrue);
    },
  );
}
