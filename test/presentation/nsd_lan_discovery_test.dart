import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/net/lan_discovery.dart';
import 'package:quizmo/presentation/discovery/nsd_lan_discovery.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.haberey/nsd');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  String? discoveryHandle;
  String? resolveHandle;
  bool delayResolve = false;
  String? errorCode;

  Future<void> callback(String method, Map<String, Object?> arguments) async {
    final done = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => done.complete(),
    );
    await done.future;
  }

  Map<String, Object?> service({String? handle}) => {
    'handle': handle,
    'service.name': 'Living room',
    'service.type': lanServiceType,
    'service.host': 'quizmo.local',
    'service.port': 8080,
    'service.addresses': '192.168.1.9',
  };

  setUp(() {
    calls.clear();
    discoveryHandle = null;
    resolveHandle = null;
    delayResolve = false;
    errorCode = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (errorCode case final code?) {
        throw PlatformException(code: code, message: 'NSD unavailable');
      }
      final arguments = Map<String, Object?>.from(call.arguments as Map);
      final handle = arguments['handle']! as String;
      switch (call.method) {
        case 'startDiscovery':
          discoveryHandle = handle;
          await callback('onDiscoveryStartSuccessful', {'handle': handle});
        case 'stopDiscovery':
          await callback('onDiscoveryStopSuccessful', {'handle': handle});
        case 'register':
          await callback('onRegistrationSuccessful', {
            ...arguments,
            'service.name': 'Living room (2)',
          });
        case 'unregister':
          await callback('onUnregistrationSuccessful', {'handle': handle});
        case 'resolve':
          resolveHandle = handle;
          if (!delayResolve) {
            await callback('onResolveSuccessful', service(handle: handle));
          }
      }
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('native advertisement has no TXT or join secrets and honors renamed instance', () async {
    final backend = NsdLanDiscovery();
    final registration = await backend.publish(name: 'Living room', port: 4321);
    final arguments = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(arguments['service.name'], 'Living room');
    expect(arguments['service.type'], '_quizmo._tcp');
    expect(arguments['service.port'], 4321);
    expect(arguments['service.host'], isNull);
    expect(arguments['service.txt'], isNull);
    expect(arguments.keys.toSet(), {
      'handle',
      'service.name',
      'service.type',
      'service.host',
      'service.port',
      'service.txt',
    });
    expect(registration.name, 'Living room (2)');
    await registration.close();
    expect(calls.last.method, 'unregister');
  });

  test(
    'DNS-SD names obey the 63-byte UTF-8 limit without splitting characters',
    () async {
      final registration = await NsdLanDiscovery().publish(
        name: '${List.filled(40, '\u00e4').join()}\n',
        port: 8080,
      );
      final arguments = Map<String, Object?>.from(calls.first.arguments as Map);
      final name = arguments['service.name']! as String;
      expect(utf8.encode(name).length, lessThanOrEqualTo(63));
      expect(name, isNot(contains('\n')));
      expect(name, isNot(contains('\ufffd')));
      await registration.close();
    },
  );

  test(
    'found services resolve, lost services vanish and browse is disposed',
    () async {
      final browser = await NsdLanDiscovery().browse();
      final subscription = browser.changes.listen((_) {});
      await callback('onServiceDiscovered', service(handle: discoveryHandle));
      await Future<void>.delayed(Duration.zero);
      expect(browser.services.single.name, 'Living room');
      expect(
        browser.services.single.addresses.first,
        Uri.parse('http://192.168.1.9:8080'),
      );
      await callback('onServiceLost', service(handle: discoveryHandle));
      expect(browser.services, isEmpty);
      await browser.close();
      await subscription.cancel();
      expect(calls.last.method, 'stopDiscovery');
    },
  );

  test('losing a service during resolve does not resurrect it', () async {
    delayResolve = true;
    final browser = await NsdLanDiscovery().browse();
    await callback('onServiceDiscovered', service(handle: discoveryHandle));
    await Future<void>.delayed(Duration.zero);
    expect(resolveHandle, isNotNull);
    await callback('onServiceLost', service(handle: discoveryHandle));
    await callback('onResolveSuccessful', service(handle: resolveHandle));
    await Future<void>.delayed(Duration.zero);
    expect(browser.services, isEmpty);
    await browser.close();
  });

  test(
    'permission and unsupported errors retain actionable categories',
    () async {
      final backend = NsdLanDiscovery();
      for (final (code, problem) in [
        ('securityIssue', LanDiscoveryProblem.permission),
        ('operationNotSupported', LanDiscoveryProblem.unsupported),
        ('internalError', LanDiscoveryProblem.unavailable),
      ]) {
        errorCode = code;
        await expectLater(
          backend.browse(),
          throwsA(
            isA<LanDiscoveryException>().having(
              (error) => error.problem,
              'problem',
              problem,
            ),
          ),
        );
      }
    },
  );

  test(
    'a missing native plugin leaves no perpetual search indicator',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException('Not installed'),
      );
      final discovery = LanDiscoveryCubit(backend: NsdLanDiscovery());
      await discovery.browse();
      expect(discovery.state.searching, isFalse);
      expect(discovery.state.problem, isNotNull);
      await discovery.close();
      expect(discovery.isClosed, isTrue);
    },
  );
}
