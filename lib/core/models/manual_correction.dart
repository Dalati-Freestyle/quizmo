import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';
import 'poker.dart';
import 'round.dart';

enum CorrectionKind { answer, buzzer, points, chips }

final class ManualCorrection extends Equatable {
  const ManualCorrection({
    required this.id,
    required this.kind,
    this.questionId,
    this.roundStartedAt,
    required this.playerId,
    required this.participantName,
    required this.beforeValue,
    required this.afterValue,
    required this.atHostMicros,
    this.teamId,
    this.reason,
    this.reversesId,
    this.scoreDeltas = const {},
    this.chipDeltas = const {},
    this.teamDeltas = const {},
    this.beforeRound,
    this.afterRound,
    this.beforeJeopardy,
    this.afterJeopardy,
    this.beforePoker,
    this.afterPoker,
    this.beforeFinished = false,
    this.afterFinished = false,
    this.wasCompleted = false,
  });

  factory ManualCorrection.fromJson(JsonMap json) => ManualCorrection(
    id: json.readString('id'),
    kind: switch (json.readString('kind')) {
      'answer' => CorrectionKind.answer,
      'buzzer' => CorrectionKind.buzzer,
      'points' => CorrectionKind.points,
      'chips' => CorrectionKind.chips,
      _ => throw const JsonContractException('Unknown correction kind.'),
    },
    questionId: json.readStringOrNull('questionId'),
    roundStartedAt: json.readIntOrNull('roundStartedAt'),
    playerId: json.readString('playerId'),
    teamId: json.readStringOrNull('teamId'),
    participantName: json.readString('participantName'),
    beforeValue: json.readIntOrNull('beforeValue'),
    afterValue: json.readIntOrNull('afterValue'),
    atHostMicros: json.readInt('atHostMicros'),
    reason: json.readStringOrNull('reason'),
    reversesId: json.readStringOrNull('reversesId'),
    scoreDeltas: json.readIntMap('scoreDeltas'),
    chipDeltas: json.readIntMap('chipDeltas'),
    teamDeltas: json['teamDeltas'] == null
        ? const {}
        : json.readIntMap('teamDeltas'),
    beforeRound: switch (json.readObjectOrNull('beforeRound')) {
      final value? => RoundState.fromJson(value),
      null => null,
    },
    afterRound: switch (json.readObjectOrNull('afterRound')) {
      final value? => RoundState.fromJson(value),
      null => null,
    },
    beforeJeopardy: switch (json.readObjectOrNull('beforeJeopardy')) {
      final value? => JeopardyState.fromJson(value),
      null => null,
    },
    afterJeopardy: switch (json.readObjectOrNull('afterJeopardy')) {
      final value? => JeopardyState.fromJson(value),
      null => null,
    },
    beforePoker: switch (json.readObjectOrNull('beforePoker')) {
      final value? => PokerState.fromJson(value),
      null => null,
    },
    afterPoker: switch (json.readObjectOrNull('afterPoker')) {
      final value? => PokerState.fromJson(value),
      null => null,
    },
    beforeFinished: json.readBool('beforeFinished'),
    afterFinished: json.readBool('afterFinished'),
    wasCompleted: json.readBool('wasCompleted'),
  );

  final String id;
  final CorrectionKind kind;

  /// Question the entry belongs to; `null` for a manual point change that
  /// is not bound to a question.
  final String? questionId;

  /// Start of the round [questionId] was played in, or `null`.
  final int? roundStartedAt;

  /// Affected player; empty when a team was changed directly.
  final String playerId;
  final String? teamId;
  final String participantName;
  final int? beforeValue;
  final int? afterValue;
  final int atHostMicros;
  final String? reason;
  final String? reversesId;
  final Map<String, int> scoreDeltas;
  final Map<String, int> chipDeltas;

  /// Points booked directly on teams (no player), per team id.
  final Map<String, int> teamDeltas;

  /// Whether a team was changed directly instead of a single player.
  bool get targetsTeam => playerId.isEmpty;
  final RoundState? beforeRound;
  final RoundState? afterRound;
  final JeopardyState? beforeJeopardy;
  final JeopardyState? afterJeopardy;
  final PokerState? beforePoker;
  final PokerState? afterPoker;
  final bool beforeFinished;
  final bool afterFinished;
  final bool wasCompleted;

  JsonMap toJson() => {
    'id': id,
    'kind': kind.name,
    'questionId': questionId,
    'roundStartedAt': roundStartedAt,
    'playerId': playerId,
    'teamId': teamId,
    'participantName': participantName,
    'beforeValue': beforeValue,
    'afterValue': afterValue,
    'atHostMicros': atHostMicros,
    'reason': reason,
    'reversesId': reversesId,
    'scoreDeltas': scoreDeltas,
    'chipDeltas': chipDeltas,
    if (teamDeltas.isNotEmpty) 'teamDeltas': teamDeltas,
    'beforeRound': beforeRound?.toJson(),
    'afterRound': afterRound?.toJson(),
    'beforeJeopardy': beforeJeopardy?.toJson(),
    'afterJeopardy': afterJeopardy?.toJson(),
    'beforePoker': beforePoker?.toJson(),
    'afterPoker': afterPoker?.toJson(),
    'beforeFinished': beforeFinished,
    'afterFinished': afterFinished,
    'wasCompleted': wasCompleted,
  };

  @override
  List<Object?> get props => [
    id,
    kind,
    questionId,
    roundStartedAt,
    playerId,
    teamId,
    participantName,
    beforeValue,
    afterValue,
    atHostMicros,
    reason,
    reversesId,
    scoreDeltas,
    chipDeltas,
    teamDeltas,
    beforeRound,
    afterRound,
    beforeJeopardy,
    afterJeopardy,
    beforePoker,
    afterPoker,
    beforeFinished,
    afterFinished,
    wasCompleted,
  ];
}
