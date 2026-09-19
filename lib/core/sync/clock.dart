/// Injectable wall clock used by the engine, the sync layer and their tests.
library;

import 'dart:math';

/// Returns the current wall clock time in microseconds since the Unix epoch.
///
/// Every time dependent component takes this typedef instead of calling
/// [DateTime.now] directly, which keeps scoring and buzzer ordering
/// deterministically testable.
typedef NowMicros = int Function();

/// The default [NowMicros] implementation, backed by [DateTime.now].
///
/// Browsers only expose millisecond resolution, so on Flutter Web the returned
/// value is effectively a millisecond value multiplied by 1000.
int systemNowMicros() => DateTime.now().microsecondsSinceEpoch;

/// Formats [micros] as a compact millisecond string such as `12.4 ms`.
String formatMicrosAsMillis(int micros) =>
    '${(micros / Duration.microsecondsPerMillisecond).toStringAsFixed(1)} ms';

/// Formats [micros] as a signed millisecond string such as `+12.4 ms`.
String formatSignedMicrosAsMillis(int micros) =>
    '${micros >= 0 ? '+' : ''}${formatMicrosAsMillis(micros)}';

final Random _random = Random();

/// Creates a short, collision resistant identifier prefixed with [prefix].
///
/// Identifiers only have to be unique within a single hosted session, so a
/// timestamp plus a random suffix is sufficient and avoids a `uuid` dependency.
String newId(String prefix) {
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final noise = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
  return '$prefix-$stamp$noise';
}

