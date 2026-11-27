import '../engine/answer_evaluation.dart';
import 'json.dart';

/// How the numbers of an estimation question are written (quiz schema 18).
///
/// The value itself is always a plain number; the time formats store
/// seconds, so scoring, tolerance and relative deviation stay the same.
enum EstimationValueFormat {
  /// A decimal number, e.g. `655` or `1,5`.
  number,

  /// Minutes and seconds, e.g. `33:58` (2038 seconds).
  minutesSeconds,

  /// Hours, minutes and seconds, e.g. `1:02:03` (3723 seconds).
  hoursMinutesSeconds;

  /// Restores a format from its stored [name]; the deserialization boundary.
  static EstimationValueFormat fromJson(Object? name) {
    for (final format in values) {
      if (format.name == name) return format;
    }
    throw JsonContractException('Unknown estimation value format "$name".');
  }

  /// Whether values are times (stored as seconds).
  bool get isTime => this != number;

  /// The pattern shown to whoever enters a value, empty for numbers.
  String get pattern => switch (this) {
    number => '',
    minutesSeconds => 'mm:ss',
    hoursMinutesSeconds => 'h:mm:ss',
  };

  /// An example in this format, for hints and error messages.
  String get example => switch (this) {
    number => '655',
    minutesSeconds => '33:58',
    hoursMinutesSeconds => '1:02:03',
  };

  /// Reads [text] in this format; `null` when it is not a valid value.
  double? parse(String text) {
    final trimmed = text.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    if (this == number) {
      final value = double.tryParse(trimmed);
      return value != null && value.isFinite ? value : null;
    }
    final match = (this == minutesSeconds ? _minutesSeconds : _hoursMinutes)
        .firstMatch(trimmed);
    if (match == null) return null;
    final negative = match.namedGroup('sign') == '-';
    final hours = this == hoursMinutesSeconds
        ? int.parse(match.namedGroup('hours')!)
        : 0;
    final minutes = int.parse(match.namedGroup('minutes')!);
    final seconds = double.parse(match.namedGroup('seconds')!);
    if (seconds >= 60) return null;
    if (this == hoursMinutesSeconds && minutes >= 60) return null;
    final total = hours * 3600 + minutes * 60 + seconds;
    return negative ? -total : total;
  }

  /// [value] written in this format: `33:58` for 2038 seconds.
  String format(double value) {
    if (this == number || !value.isFinite) return formatNumber(value);
    // Rounded to milliseconds, so 59.9999 never shows as "0:60".
    final millis = (value.abs() * 1000).round();
    final sign = value < 0 && millis > 0 ? '-' : '';
    final wholeSeconds = millis ~/ 1000;
    final fraction = millis % 1000;
    final seconds = (wholeSeconds % 60).toString().padLeft(2, '0');
    final fractionText = fraction == 0
        ? ''
        : '.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
    if (this == minutesSeconds) {
      return '$sign${wholeSeconds ~/ 60}:$seconds$fractionText';
    }
    final minutes = (wholeSeconds ~/ 60 % 60).toString().padLeft(2, '0');
    return '$sign${wholeSeconds ~/ 3600}:$minutes:$seconds$fractionText';
  }

  /// A signed difference such as `+0:12`, `-1:05` or `+12`; `±0` for none.
  String formatDeviation(double delta) {
    final text = format(delta.abs());
    if (text == format(0)) return '±$text';
    return '${delta < 0 ? '-' : '+'}$text';
  }

  static final _minutesSeconds = RegExp(
    r'^(?<sign>[-+])?(?<minutes>\d{1,6}):(?<seconds>\d{2}(?:\.\d{1,3})?)$',
  );
  static final _hoursMinutes = RegExp(
    r'^(?<sign>[-+])?(?<hours>\d{1,4}):(?<minutes>\d{2}):(?<seconds>\d{2}(?:\.\d{1,3})?)$',
  );
}
