/// Persistence of the host dashboard layout on this device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_layout.dart';

/// Reads and writes the raw layout documents.
abstract interface class DashboardLayoutBackend {
  /// Returns the stored active layout, or `null`.
  Future<String?> read();

  /// Stores the active layout [value].
  Future<void> write(String value);

  /// Returns the stored library of named layouts, or `null`.
  Future<String?> readLibrary();

  /// Stores the library of named layouts.
  Future<void> writeLibrary(String value);
}

final class _PreferencesBackend implements DashboardLayoutBackend {
  static const _key = 'quizmo.dashboard-layout.v1';
  static const _libraryKey = 'quizmo.dashboard-layouts.v1';
  late final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);

  @override
  Future<String?> readLibrary() => _preferences.getString(_libraryKey);

  @override
  Future<void> writeLibrary(String value) =>
      _preferences.setString(_libraryKey, value);
}

/// Shares the layout between the settings screen and the dashboard.
///
/// A missing or broken stored layout yields the standard layout instead of an
/// error, so the dashboard always renders. Besides the active layout the host
/// can keep named layouts in a library and switch between them.
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

  /// Named layouts of the library, sorted by name.
  final ValueNotifier<List<NamedDashboardLayout>> library = ValueNotifier(
    const [],
  );

  /// Loads the stored layout and library once.
  Future<void> load() => _loading ??= () async {
    try {
      layout.value = DashboardLayout.decode(await _backend.read());
    } on Object {
      layout.value = DashboardLayout.standard();
    }
    try {
      library.value = _sorted(
        NamedDashboardLayout.decodeLibrary(await _backend.readLibrary()),
      );
    } on Object {
      library.value = const [];
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

  /// Saves [value] under [name] in the library, replacing an entry with the
  /// same name.
  Future<void> saveAs(String name, DashboardLayout value) => _writeLibrary([
    for (final entry in library.value)
      if (entry.name != name.trim()) entry,
    NamedDashboardLayout(name: name.trim(), layout: value),
  ]);

  /// Renames the library entry [from] to [to] (replacing an entry named [to]).
  Future<void> rename(String from, String to) => _writeLibrary([
    for (final entry in library.value)
      if (entry.name == from)
        NamedDashboardLayout(name: to.trim(), layout: entry.layout)
      else if (entry.name != to.trim())
        entry,
  ]);

  /// Removes the library entry [name].
  Future<void> delete(String name) => _writeLibrary([
    for (final entry in library.value)
      if (entry.name != name) entry,
  ]);

  Future<void> _writeLibrary(List<NamedDashboardLayout> entries) async {
    library.value = _sorted(entries);
    await _backend.writeLibrary(
      NamedDashboardLayout.encodeLibrary(library.value),
    );
  }

  static List<NamedDashboardLayout> _sorted(
    List<NamedDashboardLayout> entries,
  ) => List.unmodifiable(
    [...entries]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );
}
