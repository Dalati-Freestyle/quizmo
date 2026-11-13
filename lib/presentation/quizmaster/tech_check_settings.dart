/// Latency thresholds of the technical check, stored on the host device.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/engine/tech_check.dart';

/// Reads and writes the thresholds; a broken entry yields the defaults.
class TechCheckSettingsStore {
  /// Creates the store.
  TechCheckSettingsStore();

  /// The store of this app.
  static TechCheckSettingsStore instance = TechCheckSettingsStore();

  /// Replaces [instance] (tests).
  @visibleForTesting
  static void useStore(TechCheckSettingsStore store) => instance = store;

  static const _goodKey = 'quizmo.tech-check.good-ms';
  static const _maxKey = 'quizmo.tech-check.max-ms';
  late final _preferences = SharedPreferencesAsync();

  /// The stored thresholds, or the defaults.
  Future<TechCheckThresholds> load() async {
    try {
      final good = await _preferences.getInt(_goodKey);
      final max = await _preferences.getInt(_maxKey);
      final thresholds = TechCheckThresholds(
        goodRoundTrip: Duration(
          milliseconds: good ?? TechCheckThresholds.defaultGoodMs,
        ),
        maxRoundTrip: Duration(
          milliseconds: max ?? TechCheckThresholds.defaultMaxMs,
        ),
      );
      return thresholds.isValid ? thresholds : const TechCheckThresholds();
    } on Object {
      return const TechCheckThresholds();
    }
  }

  /// Stores [thresholds]; they must be [TechCheckThresholds.isValid].
  Future<void> save(TechCheckThresholds thresholds) async {
    if (!thresholds.isValid) {
      throw ArgumentError.value(thresholds, 'thresholds');
    }
    await _preferences.setInt(
      _goodKey,
      thresholds.goodRoundTrip.inMilliseconds,
    );
    await _preferences.setInt(_maxKey, thresholds.maxRoundTrip.inMilliseconds);
  }
}
