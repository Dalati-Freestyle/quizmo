import 'package:equatable/equatable.dart';

import 'answer.dart';
import 'json.dart';

/// The input of a player that is not sent yet.
///
/// Drafts never enter the `GameState`: the host keeps the last one of every
/// player and counts it when the answers close without a sent answer.
final class AnswerDraft extends Equatable {
  const AnswerDraft({
    required this.playerId,
    required this.questionId,
    required this.roundStartedAt,
    required this.clientTimestampMicros,
    required this.clockOffsetMicros,
    this.content,
  });

  factory AnswerDraft.fromJson(JsonMap json) => AnswerDraft(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    roundStartedAt: json.readInt('roundStartedAt'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    content: switch (json.readObjectOrNull('content')) {
      final value? => AnswerSubmission.fromJson(value),
      null => null,
    },
  );

  final String playerId;
  final String questionId;

  /// Start of the round the draft belongs to; a steal round starts anew.
  final int roundStartedAt;

  /// Instant of the last change on the client clock.
  final int clientTimestampMicros;
  final int clockOffsetMicros;

  /// What is entered, `null` after it was cleared. Only its content counts.
  final AnswerSubmission? content;

  /// Instant of the last change on the host timeline (architecture rule 3).
  int get hostTimestampMicros => clientTimestampMicros - clockOffsetMicros;

  /// The connection decides whose draft it is, never the message.
  AnswerDraft withPlayerId(String id) => AnswerDraft(
    playerId: id,
    questionId: questionId,
    roundStartedAt: roundStartedAt,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    content: content?.withPlayerId(id),
  );

  JsonMap toJson() => {
    'playerId': playerId,
    'questionId': questionId,
    'roundStartedAt': roundStartedAt,
    'clientTimestampMicros': clientTimestampMicros,
    'clockOffsetMicros': clockOffsetMicros,
    if (content != null) 'content': content!.toJson(),
  };

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    roundStartedAt,
    clientTimestampMicros,
    clockOffsetMicros,
    content,
  ];
}
