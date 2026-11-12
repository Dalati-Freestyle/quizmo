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
    required this.questionId,
    required this.roundStartedAt,
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
    questionId: json.readString('questionId'),
    roundStartedAt: json.readInt('roundStartedAt'),
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
  final String questionId;
  final int roundStartedAt;
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
