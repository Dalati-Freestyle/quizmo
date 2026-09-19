/// Everything a participant can send while a round is running.
///
/// Submissions are the carrier of architecture Rule 3: a client never reports
/// "when the host should think this happened", it reports its own clock plus
/// the offset measured during the sync handshake, and the host timeline is
/// derived from those two values.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

/// Base type of every player input that competes for points.
sealed class AnswerSubmission extends Equatable {
  /// Creates the shared submission metadata.
  const AnswerSubmission({
    required this.playerId,
    required this.questionId,
    required this.clientTimestampMicros,
    required this.clockOffsetMicros,
  });

  /// Identifier of the submitting player.
  final String playerId;

  /// Question the submission belongs to; stale rounds are rejected.
  final String questionId;

  /// Instant the input happened, measured on the **client** clock.
  final int clientTimestampMicros;

  /// How far the client clock runs ahead of the host clock (`client - host`).
  final int clockOffsetMicros;

  /// The latency adjusted instant on the host timeline.
  ///
  /// This is the only value the engine may order real time events by. Ordering
  /// by packet arrival would hand the win to whoever has the better Wi-Fi.
  int get hostTimestampMicros => clientTimestampMicros - clockOffsetMicros;

  /// Returns a copy that is attributed to [id].
  ///
  /// The server calls this so a malicious client cannot submit on behalf of
  /// somebody else; the socket connection is the source of truth.
  AnswerSubmission withPlayerId(String id);

  /// Serializes the submission.
  JsonMap toJson();

  /// Restores a submission from [json].
  static AnswerSubmission fromJson(JsonMap json) =>
      switch (json.readString('kind')) {
        MultipleChoiceAnswer._kind => MultipleChoiceAnswer.fromJson(json),
        BuzzerPress._kind => BuzzerPress.fromJson(json),
        final unknown => throw JsonContractException(
          'Unknown submission kind "$unknown".',
        ),
      };

  /// Serializes the fields shared by every variant.
  ///
  /// `hostTimestampMicros` is transmitted even though it is derivable: it makes
  /// packet captures self explanatory and lets the host detect clients whose
  /// offset drifted between handshake and press.
  JsonMap baseJson(String kind) => {
    'kind': kind,
    'playerId': playerId,
    'questionId': questionId,
    'clientTimestampMicros': clientTimestampMicros,
    'clockOffsetMicros': clockOffsetMicros,
    'hostTimestampMicros': hostTimestampMicros,
  };
}

/// Selection of one option of a `MultipleChoiceQuestion`.
final class MultipleChoiceAnswer extends AnswerSubmission {
  /// Creates a multiple choice submission for [optionId].
  const MultipleChoiceAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.optionId,
  });

  /// Restores the submission from [json].
  factory MultipleChoiceAnswer.fromJson(JsonMap json) => MultipleChoiceAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    optionId: json.readString('optionId'),
  );

  static const String _kind = 'multipleChoice';

  /// Identifier of the chosen option.
  final String optionId;

  @override
  MultipleChoiceAnswer withPlayerId(String id) => MultipleChoiceAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    optionId: optionId,
  );

  @override
  JsonMap toJson() => {...baseJson(_kind), 'optionId': optionId};

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    optionId,
  ];
}

/// A buzzer hit on a `BuzzerQuestion`.
final class BuzzerPress extends AnswerSubmission {
  /// Creates a buzzer press.
  const BuzzerPress({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
  });

  /// Restores the press from [json].
  factory BuzzerPress.fromJson(JsonMap json) => BuzzerPress(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
  );

  static const String _kind = 'buzzer';

  @override
  BuzzerPress withPlayerId(String id) => BuzzerPress(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
  );

  @override
  JsonMap toJson() => baseJson(_kind);

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
  ];
}

