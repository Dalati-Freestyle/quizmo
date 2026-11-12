import 'dart:async';

import 'package:quizmo/core/net/lan_discovery.dart';

final class FakeBrowser implements LanBrowser {
  final updates = StreamController<void>.broadcast(sync: true);
  @override
  List<LanService> services = [];
  bool closed = false;
  @override
  Stream<void> get changes => updates.stream;
  void update(List<LanService> next) {
    services = next;
    updates.add(null);
  }

  @override
  Future<void> close() async {
    closed = true;
    await updates.close();
  }
}

final class FakeRegistration implements LanRegistration {
  @override
  String get name => 'Quizmo (2)';
  bool closed = false;
  @override
  Future<void> close() async => closed = true;
}

final class FakeBackend implements LanDiscoveryBackend {
  @override
  bool isSupported = true;
  final networks = StreamController<void>.broadcast(sync: true);
  final opened = StreamController<void>.broadcast(sync: true);
  final browsers = <FakeBrowser>[];
  final registrations = <FakeRegistration>[];
  final publications = <({String name, int port})>[];
  Completer<LanBrowser>? pendingBrowse;
  Completer<LanRegistration>? pendingPublication;
  Object? failure;
  @override
  Stream<void> get networkChanges => networks.stream;
  @override
  Future<LanBrowser> browse() async {
    if (failure case final error?) throw error;
    if (pendingBrowse case final pending?) return pending.future;
    final browser = FakeBrowser();
    browsers.add(browser);
    opened.add(null);
    return browser;
  }

  @override
  Future<LanRegistration> publish({
    required String name,
    required int port,
  }) async {
    if (failure case final error?) throw error;
    publications.add((name: name, port: port));
    if (pendingPublication case final pending?) return pending.future;
    final registration = FakeRegistration();
    registrations.add(registration);
    return registration;
  }

  Future<void> close() async {
    await networks.close();
    await opened.close();
  }
}
