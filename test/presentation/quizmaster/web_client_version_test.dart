@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/web_client_bundle.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/net/lan_discovery.dart';
import 'package:quizmo/presentation/quizmaster/host_server_cubit.dart';

import '../../helpers/fake_lan_discovery.dart';

InMemoryWebClientBundle _bundle(String? versionJson) =>
    InMemoryWebClientBundle({
      'index.html': Uint8List.fromList(utf8.encode('<html></html>')),
      if (versionJson != null)
        'version.json': Uint8List.fromList(utf8.encode(versionJson)),
    });

void main() {
  group('readWebClientVersion', () {
    test('combines version and build number', () async {
      expect(
        await readWebClientVersion(
          _bundle('{"version":"1.2.0","build_number":"19"}'),
        ),
        '1.2.0+19',
      );
    });

    test('is null for a missing or malformed version.json', () async {
      expect(await readWebClientVersion(_bundle(null)), isNull);
      expect(await readWebClientVersion(_bundle('not json')), isNull);
      expect(await readWebClientVersion(_bundle('[]')), isNull);
    });
  });

  group('HostServerCubit web player version check', () {
    Future<HostServerCubit> startHost(
      String webVersion,
      String appVersion,
    ) async {
      final backend = FakeBackend();
      final engine = QuizEngineBloc();
      final host = HostServerCubit(
        engine: engine,
        discovery: LanDiscoveryCubit(backend: backend),
        webClient: _bundle(webVersion),
        appVersion: () async => appVersion,
      );
      addTearDown(() async {
        await host.close();
        await engine.close();
        await backend.close();
      });
      await host.start(port: 0);
      return host;
    }

    test(
      'flags a stale bundle so TV screens are not silently outdated',
      () async {
        final host = await startHost(
          '{"version":"1.0.0","build_number":"1"}',
          '1.2.0+19',
        );
        expect(host.state.servesWebClient, isTrue);
        expect(host.state.outdatedWebClientVersion, '1.0.0+1');
        expect(
          host.state.logs.map((entry) => entry.message),
          contains(contains('web player is version 1.0.0+1')),
        );
      },
    );

    test('stays quiet when the bundle matches the host', () async {
      final host = await startHost(
        '{"version":"1.2.0","build_number":"19"}',
        '1.2.0+19',
      );
      expect(host.state.outdatedWebClientVersion, isNull);
      await host.stop();
      expect(host.state.outdatedWebClientVersion, isNull);
    });
  });
}
