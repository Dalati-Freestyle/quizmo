/// Persistence of the host dashboard layout on this device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_layout.dart';

/// Reads and writes the raw layout document.
abstract interface class DashboardLayoutBackend {
  /// Returns the stored document, or `null`.
  Future<String?> read();

  /// Stores [value].
  Future<void> write(String value);
}

final class _PreferencesBackend implements DashboardLayoutBackend {
  static const _key = 'quizmo.dashboard-layout.v1';
  late final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);
}

/// Shares the layout between the settings screen and the dashboard.
///
/// A missing or broken stored layout yields the standard layout instead of an
/// error, so the dashboard always renders.
final class DashboardLayoutStore {
  DashboardLayoutStore._(this._backend);

  /// The store of this app.
  static DashboardLayoutStore instance = DashboardLayoutStore._(
    _PreferencesBackend(),
  );

  /// Replaces [instance] (tests).
  @visibleForTesting
  static void useBackend(DashboardLayoutBackend backend) =>
      instance = DashboardLayoutStore._(backend);

  final DashboardLayoutBackend _backend;
  Future<void>? _loading;

  /// The current layout; listeners rebuild when it changes.
  final ValueNotifier<DashboardLayout> layout = ValueNotifier(
    DashboardLayout.standard(),
  );

  /// Loads the stored layout once.
  Future<void> load() => _loading ??= () async {
    try {
      layout.value = DashboardLayout.decode(await _backend.read());
    } on Object {
      layout.value = DashboardLayout.standard();
    }
  }();

  /// Applies [value] and stores it in the background. A failed write keeps
  /// the layout for this session instead of disturbing the game.
  void remember(DashboardLayout value) {
    layout.value = value;
    unawaited(
      _backend.write(value.encode()).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  /// Applies and stores [value]. The new layout applies even if storing fails.
  Future<void> save(DashboardLayout value) async {
    layout.value = value;
    await _backend.write(value.encode());
  }
}
