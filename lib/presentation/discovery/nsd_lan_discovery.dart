import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../../backend/lan_addresses.dart';
import '../../core/net/lan_discovery.dart';

LanDiscoveryBackend createLanDiscoveryBackend() => NsdLanDiscovery();

final class NsdLanDiscovery implements LanDiscoveryBackend {
  @override
  bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  Stream<void> get networkChanges {
    late final StreamController<void> changes;
    Timer? timer;
    String? previous;
    bool cancelled = false;
    bool checking = false;
    Future<void> check() async {
      if (checking || cancelled) return;
      checking = true;
      try {
        final fingerprint = await _networkFingerprint();
        if (cancelled) return;
        if (previous != null && previous != fingerprint) changes.add(null);
        previous = fingerprint;
      } on Object catch (error, stack) {
        if (!cancelled) changes.addError(error, stack);
      } finally {
        checking = false;
      }
    }

    changes = StreamController<void>(
      onListen: () {
        unawaited(check());
        timer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(check()),
        );
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return changes.stream;
  }

  @override
  Future<LanBrowser> browse() => _native(() async {
    final discovery = await nsd.startDiscovery(
      lanServiceType,
      autoResolve: false,
    );
    return _NsdBrowser(discovery);
  });

  @override
  Future<LanRegistration> publish({
    required String name,
    required int port,
  }) => _native(() async {
    // No TXT records: only the friendly name, type, host and listening port.
    final registration = await nsd.register(
      nsd.Service(name: _serviceName(name), type: lanServiceType, port: port),
    );
    return _NsdRegistration(registration);
  });
}

Future<String> _networkFingerprint() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final addresses = [
    for (final interface in interfaces)
      for (final address in interface.addresses)
        '${interface.name}:${address.address}',
  ]..sort();
  return addresses.join(',');
}

String _serviceName(String name) {
  final clean = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  final result = StringBuffer();
  for (final rune in (clean.isEmpty ? 'Quizmo Host' : clean).runes) {
    final character = String.fromCharCode(rune);
    if (utf8.encode('$result$character').length > 63) break;
    result.write(character);
  }
  return result.toString();
}

Future<T> _native<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on nsd.NsdError catch (error) {
    throw LanDiscoveryException(switch (error.cause) {
      nsd.ErrorCause.securityIssue => LanDiscoveryProblem.permission,
      nsd.ErrorCause.operationNotSupported => LanDiscoveryProblem.unsupported,
      _ => LanDiscoveryProblem.unavailable,
    }, '$error');
  } on MissingPluginException catch (error) {
    throw LanDiscoveryException(LanDiscoveryProblem.unsupported, '$error');
  } on PlatformException catch (error) {
    throw LanDiscoveryException(LanDiscoveryProblem.unavailable, '$error');
  }
}

final class _NsdRegistration implements LanRegistration {
  _NsdRegistration(this.registration);
  final nsd.Registration registration;
  @override
  String get name => registration.service.name ?? 'Quizmo Host';
  @override
  Future<void> close() => _native(() => nsd.unregister(registration));
}

final class _NsdBrowser implements LanBrowser {
  _NsdBrowser(this.discovery) {
    discovery.addServiceListener(_changed);
    for (final service in discovery.services) {
      _changed(service, nsd.ServiceStatus.found);
    }
  }
  final nsd.Discovery discovery;
  final _changes = StreamController<void>.broadcast();
  final _resolved = <String, nsd.Service>{};
  final _versions = <String, int>{};
  Future<void> _resolving = Future.value();
  bool _closed = false;

  void _changed(nsd.Service service, nsd.ServiceStatus status) {
    final key = '${service.name}|${service.type}';
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    if (status == nsd.ServiceStatus.lost) {
      _resolved.remove(key);
      _changes.add(null);
      return;
    }
    _resolving = _resolving.then((_) async {
      if (_closed || _versions[key] != version) return;
      try {
        var resolved = await _native(() => nsd.resolve(service));
        if (resolved.addresses == null && resolved.host != null) {
          final addresses = await InternetAddress.lookup(
            resolved.host!,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(seconds: 2));
          resolved = nsd.Service(
            name: resolved.name,
            type: resolved.type,
            host: resolved.host,
            port: resolved.port,
            addresses: addresses,
          );
        }
        if (_closed || _versions[key] != version) return;
        _resolved[key] = resolved;
        _changes.add(null);
      } on Object catch (error, stack) {
        if (!_closed && _versions[key] == version) {
          _changes.addError(error, stack);
        }
      }
    });
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  List<LanService> get services => [
    for (final service in _resolved.values)
      if (service.port case final port? when port > 0 && port <= 65535)
        if (service.name case final name?)
          LanService(
            id: '$name|${service.host}|$port',
            name: name,
            addresses: [
              for (final address in sortLanAddresses([
                for (final address in service.addresses ?? <InternetAddress>[])
                  LanAddressCandidate(
                    address: address.address,
                    interfaceName: '',
                  ),
              ]))
                if (address != kLoopbackAddress)
                  Uri(scheme: 'http', host: address, port: port),
              if (service.host case final host? when host.isNotEmpty)
                Uri(scheme: 'http', host: host, port: port),
            ],
          ),
  ];

  @override
  Future<void> close() async {
    await _native(() => nsd.stopDiscovery(discovery));
    _closed = true;
    discovery.removeServiceListener(_changed);
    discovery.dispose();
    await _changes.close();
  }
}
