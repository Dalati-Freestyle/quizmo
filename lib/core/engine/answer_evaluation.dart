import 'dart:math' as math;

String normalizeAnswer(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A non-binding suggestion for the host's manual text-answer assessment.
enum TextAnswerRecommendation { exactMatch, possibleTypo, different }

/// Compares [input] with the solutions using the configured typo tolerance.
TextAnswerRecommendation recommendTextAnswer(
  String input,
  List<String> acceptedAnswers,
  int maxEdits,
) {
  final normalized = normalizeAnswer(input);
  if (normalized.isEmpty) return TextAnswerRecommendation.different;
  if (acceptedAnswers.any((answer) => normalizeAnswer(answer) == normalized)) {
    return TextAnswerRecommendation.exactMatch;
  }
  return acceptedAnswers.any((answer) => fuzzyEquals(input, answer, maxEdits))
      ? TextAnswerRecommendation.possibleTypo
      : TextAnswerRecommendation.different;
}

bool fuzzyEquals(String input, String expected, int maxEdits) {
  final a = normalizeAnswer(input).runes.toList();
  final b = normalizeAnswer(expected).runes.toList();
  if (a.isEmpty || (a.length - b.length).abs() > maxEdits) return false;
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final row = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      row.add(
        math.min(
          math.min(row[j] + 1, previous[j + 1] + 1),
          previous[j] + (a[i] == b[j] ? 0 : 1),
        ),
      );
    }
    if (row.reduce(math.min) > maxEdits) return false;
    previous = row;
  }
  return previous.last <= maxEdits;
}

/// [value] without a needless fraction: `330` instead of `330.0`.
String formatNumber(double value) =>
    value.isFinite && value == value.roundToDouble() && value.abs() < 1e15
    ? value.toStringAsFixed(0).replaceFirst(RegExp(r'^-0$'), '0')
    : '$value';

/// Accuracy of an estimation that may have a tolerance: everything from [min]
/// to [max] (both included) is fully correct, nothing outside ever is. With
/// [toleranceOnly] an answer outside the tolerance earns nothing at all.
double estimationAccuracyWithin(
  double value,
  double target,
  double zeroScale, {
  double? min,
  double? max,
  bool toleranceOnly = false,
}) {
  if (min == null || max == null) {
    return estimationAccuracy(value, target, zeroScale);
  }
  if (value >= min && value <= max) return 1;
  if (toleranceOnly) return 0;
  return math.min(estimationAccuracy(value, target, zeroScale), 0.999999);
}

double estimationAccuracy(double value, double target, double zeroScale) =>
    (1 - (value - target).abs() / (target == 0 ? zeroScale : target.abs()))
        .clamp(0.0, 1.0);
