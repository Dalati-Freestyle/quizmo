/// Labels shared by the protocol view and the protocol PDF.
///
/// Both render the same [GameProtocol]; keeping the wording in one place makes
/// the downloaded file read exactly like the screen.
library;

import '../../core/models/game_protocol.dart';

/// Translates a message key with optional `{n}` arguments.
typedef Translate = String Function(String key, [List<Object?> arguments]);

/// Message key describing [status].
String protocolStatusKey(ProtocolAnswerStatus status) => switch (status) {
  ProtocolAnswerStatus.correct => 'Richtig',
  ProtocolAnswerStatus.partial => 'Teilweise richtig',
  ProtocolAnswerStatus.incorrect => 'Wrong',
  ProtocolAnswerStatus.ungraded => 'Unbewertet',
  ProtocolAnswerStatus.noAnswer => 'Keine Antwort',
  ProtocolAnswerStatus.notEligible => 'Nicht berechtigt',
  ProtocolAnswerStatus.teamAnswered => 'Team hat geantwortet',
};

/// Message key describing a correction [kind].
String protocolCorrectionKey(ProtocolCorrectionKind kind) => switch (kind) {
  ProtocolCorrectionKind.answer => 'Manuelle Bewertung',
  ProtocolCorrectionKind.buzzer => 'Buzzer-Bewertung',
  ProtocolCorrectionKind.points => 'Punkteänderung',
  ProtocolCorrectionKind.chips => 'Chipänderung',
};

/// Message key of the quiz format.
String protocolFormatKey(ProtocolFormat format) => switch (format) {
  ProtocolFormat.standard => 'Standard',
  ProtocolFormat.jeopardy => 'Jeopardy',
  ProtocolFormat.poker => 'Pokerchips',
};

/// Unit of scores in [protocol] ("Punkte" or "Chips").
String protocolUnit(GameProtocol protocol, Translate tr) =>
    protocol.usesChips ? tr('Chips') : tr('Punkte');

/// Formats [micros] as local `dd.MM.yyyy HH:mm`.
String protocolDateTime(int micros) {
  final time = DateTime.fromMicrosecondsSinceEpoch(micros).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// Formats [micros] as local `HH:mm:ss`.
String protocolTime(int micros) {
  final time = DateTime.fromMicrosecondsSinceEpoch(micros).toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Signed number, e.g. `+5` or `-3`.
String signed(int value) => value > 0 ? '+$value' : '$value';

/// Short tags of a question (category, points, steal, Daily Double).
List<String> protocolQuestionTags(ProtocolQuestion question, Translate tr) => [
  ?question.category,
  if (question.pointsAtStake case final points?) tr('{0} Punkte', [points]),
  if (question.isSteal) tr('Steal'),
  if (question.isDailyDouble) tr('Daily Double'),
];

/// Readable value of a correction (before → after).
String protocolCorrectionChange(ProtocolCorrection entry, Translate tr) {
  String value(int? number) => switch (entry.kind) {
    ProtocolCorrectionKind.answer || ProtocolCorrectionKind.buzzer =>
      number == null
          ? tr('Unbewertet')
          : number == 1
          ? tr('Richtig')
          : tr('Wrong'),
    _ => number?.toString() ?? '–',
  };
  return '${value(entry.before)} → ${value(entry.after)}';
}
