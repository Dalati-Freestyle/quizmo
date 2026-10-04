import 'dart:math' as math;

String normalizeAnswer(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

double estimationAccuracy(double value, double target, double zeroScale) =>
    (1 - (value - target).abs() / (target == 0 ? zeroScale : target.abs()))
        .clamp(0.0, 1.0);
