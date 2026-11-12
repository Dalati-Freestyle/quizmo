import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:http/http.dart' as http;

import '../sync/clock.dart';

const lanServiceType = '_quizmo._tcp';

enum LanDiscoveryProblem { unsupported, permission, unavailable }

class LanDiscoveryException implements Exception {
  const LanDiscoveryException(this.problem, this.details);
  final LanDiscoveryProblem problem;
  final String details;
  @override
  String toString() => details;
}

final class LanService {
  LanService({
    required this.id,
    required this.name,
    required Iterable<Uri> addresses,
  }) : addresses = List.unmodifiable(addresses);

  final String id;
  final String name;
  final List<Uri> addresses;
}

final class LanHost {
  const LanHost({required this.service, this.reachableUri});
  final LanService service;
  final Uri? reachableUri;
}

abstract interface class LanBrowser {
  List<LanService> get services;
  Stream<void> get changes;
  Future<void> close();
}

abstract interface class LanRegistration {
  String get name;
  Future<void> close();
}

abstract interface class LanDiscoveryBackend {
  bool get isSupported;
  Stream<void> get networkChanges;
  Future<LanBrowser> browse();
  Future<LanRegistration> publish({required String name, required int port});
}

typedef LanReachability = Future<bool> Function(Uri uri);

Future<bool> probeLanHost(Uri uri) async {
  final client = http.Client();
  try {
    final response = await client
        .get(uri.replace(path: '/api/health'))
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body);
    return body is Map<String, dynamic> &&
        body['status'] == 'ok' &&
        body['serverName'] is String &&
        body['hostTimeMicros'] is int &&
        body['players'] is int;
  } on TimeoutException {
    return false;
  } on http.ClientException {
    return false;
  } on FormatException {
    return false;
  } finally {
    client.close();
  }
}

final class LanDiscoveryState {
  const LanDiscoveryState({
    this.hosts = const [],
    this.searching = false,
    this.publishedName,
    this.problem,
    this.details,
  });
  final List<LanHost> hosts;
  final bool searching;
  final String? publishedName;
  final LanDiscoveryProblem? problem;
  final String? details;
}

// All native resource operations are serialized. Revisions invalidate callbacks
// immediately, even when a native start/resolve is still in flight.
final class LanDiscoveryCubit extends Cubit<LanDiscoveryState> {
  LanDiscoveryCubit({
    required LanDiscoveryBackend backend,
    LanReachability probe = probeLanHost,
    NowMicros now = systemNowMicros,
    this.refreshInterval = const Duration(seconds: 20),
  }) : _backend = backend,
       _probe = probe,
       _now = now,
       super(const LanDiscoveryState());

  final LanDiscoveryBackend _backend;
  final LanReachability _probe;
  final NowMicros _now;
  final _lastReachableOrSeen = <String, int>{};
  final Duration refreshInterval;
  LanBrowser? _browser;
  LanRegistration? _registration;
  StreamSubscription<void>? _services;
  StreamSubscription<void>? _network;
  Timer? _timer;
  Future<void> _pending = Future.value();
  int _revision = 0;
  int _snapshot = 0;
  bool _browse = false;
  bool _suspended = false;
  bool _closing = false;
  ({String name, int port})? _publication;

  Future<void> browse() {
    _browse = true;
    return refresh();
  }

  Future<void> publish({required String name, required int port}) {
    _publication = (name: name, port: port);
    return refresh();
  }

  Future<void> setSuspended(bool suspended) {
    if (_suspended == suspended) return _pending;
    _suspended = suspended;
    return refresh();
  }

  Future<void> stop() {
    _browse = false;
    _publication = null;
    _lastReachableOrSeen.clear();
    return refresh();
  }

  Future<void> refresh() {
    if (_closing) return _pending;
    final revision = ++_revision;
    _timer?.cancel();
    final networkCleanup = _network?.cancel();
    _network = null;
    emit(const LanDiscoveryState());
    _pending = _pending.then(
      (_) => _restart(revision, networkCleanup: networkCleanup),
    );
    return _pending;
  }

  Future<void> _release() async {
    await _services?.cancel();
    _services = null;
    await _network?.cancel();
    _network = null;
    try {
      if (_browser case final browser?) {
        await browser.close();
        _browser = null;
      }
    } finally {
      if (_registration case final registration?) {
        await registration.close();
        _registration = null;
      }
    }
  }

  bool _current(int revision) => !_closing && revision == _revision;

  Future<void> _restart(int revision, {Future<void>? networkCleanup}) async {
    try {
      await networkCleanup;
      await _release();
      if (!_current(revision) ||
          _suspended ||
          (!_browse && _publication == null)) {
        return;
      }
      if (!_backend.isSupported) {
        emit(const LanDiscoveryState(problem: LanDiscoveryProblem.unsupported));
        return;
      }
      _network = _backend.networkChanges.listen(
        (_) => unawaited(refresh()),
        onError: (Object error) => _failure(error, revision),
      );
      if (_publication case final publication?) {
        _registration = await _backend.publish(
          name: publication.name,
          port: publication.port,
        );
      }
      if (!_current(revision)) return;
      if (_browse) {
        emit(const LanDiscoveryState(searching: true));
        _browser = await _backend.browse();
        if (!_current(revision)) return;
        _services = _browser!.changes.listen(
          (_) => unawaited(_readServices(revision)),
          onError: (Object error) => _failure(error, revision),
        );
        unawaited(_readServices(revision));
        // A fresh browse also evicts cached services after missed goodbye
        // packets and recovers when multicast or the network becomes available.
        _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
      } else {
        emit(LanDiscoveryState(publishedName: _registration?.name));
      }
    } on Object catch (error) {
      _failure(error, revision);
    }
  }

  Future<void> _readServices(int revision) async {
    if (!_current(revision)) return;
    final snapshot = ++_snapshot;
    final services = _browser?.services ?? const <LanService>[];
    // Publish removals before any reachability request can delay them.
    final ids = services.map((service) => service.id).toSet();
    emit(
      LanDiscoveryState(
        searching: true,
        hosts: state.hosts
            .where((host) => ids.contains(host.service.id))
            .toList(),
      ),
    );
    try {
      final hosts = await Future.wait(
        services.map((service) async {
          Uri? reachable;
          for (final address in service.addresses) {
            if (await _probe(address)) {
              reachable = address;
              break;
            }
            if (!_current(revision) || snapshot != _snapshot) break;
          }
          if (!_current(revision) || snapshot != _snapshot) return null;
          final now = _now();
          final lastSeen = _lastReachableOrSeen.putIfAbsent(
            service.id,
            () => now,
          );
          if (reachable != null) {
            _lastReachableOrSeen[service.id] = now;
          } else if (now - lastSeen >= refreshInterval.inMicroseconds) {
            return null;
          }
          return LanHost(service: service, reachableUri: reachable);
        }),
      );
      if (!_current(revision) || snapshot != _snapshot) return;
      final visible = hosts.whereType<LanHost>().toList();
      visible.sort((a, b) {
        final byName = a.service.name.compareTo(b.service.name);
        return byName != 0 ? byName : a.service.id.compareTo(b.service.id);
      });
      emit(
        LanDiscoveryState(hosts: List.unmodifiable(visible), searching: false),
      );
    } on Object catch (error) {
      _failure(error, revision);
    }
  }

  void _failure(Object error, int revision) {
    if (!_current(revision)) return;
    emit(
      LanDiscoveryState(
        problem: error is LanDiscoveryException
            ? error.problem
            : LanDiscoveryProblem.unavailable,
        details: '$error',
      ),
    );
  }

  @override
  Future<void> close() async {
    _closing = true;
    ++_revision;
    _timer?.cancel();
    final networkCleanup = _network?.cancel();
    _network = null;
    await _pending;
    try {
      await networkCleanup;
      await _release();
    } on Object catch (error) {
      // The owner still receives cleanup failures rather than a false success.
      addError(error, StackTrace.current);
      rethrow;
    } finally {
      await super.close();
    }
  }
}
