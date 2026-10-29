import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/net/lan_discovery.dart';
import 'package:quizmo/presentation/discovery/lan_host_list.dart';
import 'package:quizmo/presentation/discovery/lan_discovery_stub.dart' as stub;

import '../helpers/fake_lan_discovery.dart';

LanService service(String id, String address, {String name = 'Living room'}) =>
    LanService(id: id, name: name, addresses: [Uri.parse(address)]);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('LAN discovery lifecycle', () {
    late FakeBackend backend;
    late LanDiscoveryCubit discovery;
    setUp(() {
      backend = FakeBackend();
      discovery = LanDiscoveryCubit(backend: backend, probe: (_) async => true);
    });
    tearDown(() async {
      if (!discovery.isClosed) await discovery.close();
      await backend.close();
    });

    test('same names remain distinct and lost services disappear', () async {
      await discovery.browse();
      final browser = backend.browsers.single;
      final a = service('a', 'http://192.168.1.2:8080');
      final b = service('b', 'http://192.168.1.3:8080');
      browser.update([a, b]);
      await settle();
      expect(discovery.state.hosts.map((host) => host.service.id), ['a', 'b']);
      expect(discovery.state.hosts.map((host) => host.reachableUri), [
        a.addresses.single,
        b.addresses.single,
      ]);
      browser.update([b]);
      expect(discovery.state.hosts.single.service.id, 'b');
      await settle();
      browser.update([]);
      expect(discovery.state.hosts, isEmpty);
    });

    test('manual refresh closes old browse and clears stale hosts', () async {
      await discovery.browse();
      final browser = backend.browsers.single;
      browser.update([service('a', 'http://192.168.1.2:8080')]);
      await settle();
      await discovery.refresh();
      expect(browser.closed, isTrue);
      expect(backend.browsers.length, 2);
      expect(discovery.state.hosts, isEmpty);
    });

    test('network change replaces browser and registration', () async {
      await discovery.publish(name: 'Quizmo', port: 4321);
      await discovery.browse();
      final browser = backend.browsers.single;
      final registration = backend.registrations.last;
      backend.networks.add(null);
      await settle();
      expect(browser.closed, isTrue);
      expect(registration.closed, isTrue);
      expect(backend.browsers.length, 2);
      expect(backend.publications.last, (name: 'Quizmo', port: 4321));
    });

    test(
      'pause releases resources; resume restarts; stop stays stopped',
      () async {
        await discovery.publish(name: 'Quizmo', port: 1234);
        await discovery.browse();
        await discovery.setSuspended(true);
        expect(backend.browsers.every((browser) => browser.closed), isTrue);
        expect(backend.registrations.every((entry) => entry.closed), isTrue);
        expect(backend.networks.hasListener, isFalse);
        await discovery.setSuspended(false);
        expect(backend.browsers.last.closed, isFalse);
        await discovery.stop();
        final count = backend.browsers.length;
        await discovery.setSuspended(true);
        await discovery.setSuspended(false);
        expect(backend.browsers.length, count);
      },
    );

    test('close during pending browse still disposes late resource', () async {
      backend.pendingBrowse = Completer<LanBrowser>();
      final starting = discovery.browse();
      await settle();
      final closing = discovery.close();
      expect(backend.networks.hasListener, isFalse);
      final browser = FakeBrowser();
      backend.pendingBrowse!.complete(browser);
      await starting;
      await closing;
      expect(browser.closed, isTrue);
      expect(backend.networks.hasListener, isFalse);
    });

    test('stop during registration unregisters its late result', () async {
      backend.pendingPublication = Completer<LanRegistration>();
      final starting = discovery.publish(name: 'Quizmo', port: 8080);
      await settle();
      final stopping = discovery.stop();
      final registration = FakeRegistration();
      backend.pendingPublication!.complete(registration);
      await starting;
      await stopping;
      expect(registration.closed, isTrue);
      expect(discovery.state.publishedName, isNull);
    });

    test('OS name collision result is exposed', () async {
      await discovery.publish(name: 'Quizmo', port: 8080);
      expect(discovery.state.publishedName, 'Quizmo (2)');
    });

    test('unsupported platforms never invoke native operations', () async {
      backend.isSupported = false;
      await discovery.browse();
      expect(discovery.state.problem, LanDiscoveryProblem.unsupported);
      expect(backend.browsers, isEmpty);
      expect(backend.networks.hasListener, isFalse);
    });

    test('permission failure is explicit and refresh can recover', () async {
      backend.failure = const LanDiscoveryException(
        LanDiscoveryProblem.permission,
        'Permission denied',
      );
      await discovery.browse();
      expect(discovery.state.problem, LanDiscoveryProblem.permission);
      expect(discovery.state.details, 'Permission denied');
      backend.failure = null;
      await discovery.refresh();
      await settle();
      expect(discovery.state.problem, isNull);
      expect(backend.browsers, hasLength(1));
    });

    test('periodic fresh browse evicts hosts after missed goodbye', () async {
      await discovery.close();
      discovery = LanDiscoveryCubit(
        backend: backend,
        probe: (_) async => true,
        refreshInterval: const Duration(milliseconds: 30),
      );
      await discovery.browse();
      final browser = backend.browsers.single;
      browser.update([service('a', 'http://192.168.1.2:8080')]);
      await settle();
      final nextBrowse = backend.opened.stream.first;
      await nextBrowse.timeout(const Duration(seconds: 2));
      expect(browser.closed, isTrue);
      expect(discovery.state.hosts, isEmpty);
    });
  });

  test(
    'address alternatives are probed, unreachable hosts cannot be joined',
    () async {
      final backend = FakeBackend();
      final calls = <Uri>[];
      final discovery = LanDiscoveryCubit(
        backend: backend,
        probe: (uri) async {
          calls.add(uri);
          return uri.host == '192.168.1.2';
        },
      );
      await discovery.browse();
      final addresses = [
        Uri.parse('http://192.0.0.4:8080'),
        Uri.parse('http://192.168.1.2:8080'),
      ];
      backend.browsers.single.update([
        LanService(id: 'a', name: 'Quizmo', addresses: addresses),
        service('b', 'http://192.168.1.3:8080'),
      ]);
      await settle();
      expect(calls, containsAll(addresses));
      expect(
        discovery.state.hosts
            .singleWhere((host) => host.service.id == 'a')
            .reachableUri,
        addresses.last,
      );
      expect(
        discovery.state.hosts
            .singleWhere((host) => host.service.id == 'b')
            .reachableUri,
        isNull,
      );
      await discovery.close();
      await backend.close();
    },
  );

  test('a removed service cannot be resurrected by a late probe', () async {
    final backend = FakeBackend();
    final pending = Completer<bool>();
    final discovery = LanDiscoveryCubit(
      backend: backend,
      probe: (_) => pending.future,
    );
    await discovery.browse();
    backend.browsers.single.update([service('a', 'http://192.168.1.2:8080')]);
    backend.browsers.single.update([]);
    pending.complete(true);
    await settle();
    expect(discovery.state.hosts, isEmpty);
    await discovery.close();
    await backend.close();
  });

  test(
    'unreachable OS-cached services expire and recover when reachable',
    () async {
      final backend = FakeBackend();
      var now = 0;
      var reachable = true;
      final discovery = LanDiscoveryCubit(
        backend: backend,
        now: () => now,
        probe: (_) async => reachable,
      );
      await discovery.browse();
      final cached = service('a', 'http://192.168.1.2:8080');
      backend.browsers.last.update([cached]);
      await settle();
      expect(discovery.state.hosts, hasLength(1));
      reachable = false;
      now = const Duration(seconds: 20).inMicroseconds;
      await discovery.refresh();
      backend.browsers.last.update([cached]);
      await settle();
      expect(discovery.state.hosts, isEmpty);
      reachable = true;
      backend.browsers.last.update([cached]);
      await settle();
      expect(
        discovery.state.hosts.single.reachableUri,
        cached.addresses.single,
      );
      await discovery.close();
      await backend.close();
    },
  );

  test('web stub is unsupported without importing a native adapter', () async {
    final backend = stub.createLanDiscoveryBackend();
    expect(backend.isSupported, isFalse);
    await expectLater(backend.browse(), throwsA(isA<LanDiscoveryException>()));
  });

  testWidgets(
    'host list disambiguates names and selects only reachable hosts',
    (tester) async {
      final backend = FakeBackend();
      final discovery = LanDiscoveryCubit(
        backend: backend,
        probe: (uri) async => uri.host == '192.168.1.2',
      );
      Uri? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LanHostList(
              discovery: discovery,
              onSelected: (uri) => selected = uri,
            ),
          ),
        ),
      );
      await tester.pump();
      backend.browsers.single.update([
        service('a', 'http://192.168.1.2:8080'),
        service('b', 'http://192.168.1.3:8080'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Living room'), findsNWidgets(2));
      expect(find.textContaining('192.168.1.2'), findsOneWidget);
      expect(find.textContaining('192.168.1.3'), findsOneWidget);
      await tester.tap(find.textContaining('192.168.1.3'));
      expect(selected, isNull);
      await tester.tap(find.textContaining('192.168.1.2'));
      expect(selected, Uri.parse('http://192.168.1.2:8080'));
      await tester.tap(find.byTooltip('Refresh LAN games'));
      await tester.pump();
      expect(find.text('Living room'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(discovery.isClosed, isTrue);
      expect(backend.browsers.every((browser) => browser.closed), isTrue);
      await backend.close();
    },
  );
}
