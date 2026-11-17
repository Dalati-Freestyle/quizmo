/// Latency thresholds of the technical check, stored on the host device.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/engine/tech_check.dart';

/// Reads and writes the thresholds for LAN and internet games separately;
/// a missing or broken entry yields the defaults of that mode.
class TechCheckSettingsStore {
  /// Creates the store.
  TechCheckSettingsStore();

  /// The store of this app.
  static TechCheckSettingsStore instance = TechCheckSettingsStore();

  /// Replaces [instance] (tests).
  @visibleForTesting
  static void useStore(TechCheckSettingsStore store) => instance = store;

  late final _preferences = SharedPreferencesAsync();

  static String _key(String value, {required bool internet}) =>
      'quizmo.tech-check.${internet ? 'internet' : 'lan'}.$value-ms';

  /// The stored thresholds of the mode, or its defaults.
  Future<TechCheckThresholds> load({required bool internet}) async {
    final defaults = TechCheckThresholds.defaultsFor(internet: internet);
    try {
      final good = await _preferences.getInt(_key('good', internet: internet));
      final max = await _preferences.getInt(_key('max', internet: internet));
      final thresholds = TechCheckThresholds(
        goodRoundTrip: good == null
            ? defaults.goodRoundTrip
            : Duration(milliseconds: good),
        maxRoundTrip: max == null
            ? defaults.maxRoundTrip
            : Duration(milliseconds: max),
      );
      return thresholds.isValid ? thresholds : defaults;
    } on Object {
      return defaults;
    }
  }

  /// Stores [thresholds] of the mode; they must be
  /// [TechCheckThresholds.isValid].
  Future<void> save(
    TechCheckThresholds thresholds, {
    required bool internet,
  }) async {
    if (!thresholds.isValid) {
      throw ArgumentError.value(thresholds, 'thresholds');
    }
    await _preferences.setInt(
      _key('good', internet: internet),
      thresholds.goodRoundTrip.inMilliseconds,
    );
    await _preferences.setInt(
      _key('max', internet: internet),
      thresholds.maxRoundTrip.inMilliseconds,
    );
  }
}
