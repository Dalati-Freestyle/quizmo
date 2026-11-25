import '../../core/models/models.dart';

/// "Eliminated at question N" for a poker team that is out, else `null`.
String? eliminationLabel(
  String Function(String key, [List<Object?> args]) tr,
  PokerState? poker,
  String teamId,
) => eliminatedAtLabel(tr, poker?.eliminations[teamId]);

/// The same for a stored moment ([ProtocolStanding.eliminatedAt]).
String? eliminatedAtLabel(
  String Function(String key, [List<Object?> args]) tr,
  int? question,
) => switch (question) {
  null => null,
  0 => tr('Ausgeschieden'),
  final number => tr('Ausgeschieden bei Frage {0}', [number]),
};
