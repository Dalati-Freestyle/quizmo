/// Everything a participant can send while a round is running.
///
/// Submissions are the carrier of architecture Rule 3: a client never reports
/// "when the host should think this happened", it reports its own clock plus
/// the offset measured during the sync handshake, and the host timeline is
/// derived from those two values.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

/// Whether [a] and [b] say the same, no matter who sent them when.
bool sameAnswerContent(AnswerSubmission a, AnswerSubmission b) => switch ((
  a,
  b,
)) {
  (final MultipleChoiceAnswer a, final MultipleChoiceAnswer b) =>
    a.selectedOptionIds.length == b.selectedOptionIds.length &&
        a.selectedOptionIds.toSet().containsAll(b.selectedOptionIds),
  (final ShortAnswer a, final ShortAnswer b) => a.text.trim() == b.text.trim(),
  (final OrderingAnswer a, final OrderingAnswer b) =>
    a.itemIds.length == b.itemIds.length &&
        a.itemIds.indexed.every((e) => e.$2 == b.itemIds[e.$1]),
  (final MatchingAnswer a, final MatchingAnswer b) =>
    a.pairs.length == b.pairs.length &&
        a.pairs.entries.every((e) => b.pairs[e.key] == e.value),
  (final EstimationAnswer a, final EstimationAnswer b) => a.value == b.value,
  (final TrueFalseAnswer a, final TrueFalseAnswer b) => a.value == b.value,
  (final LocationAnswer a, final LocationAnswer b) =>
    a.latitude == b.latitude && a.longitude == b.longitude,
  _ => false,
};

/// Orders answers of one team: by the calculated host time, never by arrival;
/// equal instants are told apart by the player id.
int compareAnswerOrder(AnswerSubmission a, AnswerSubmission b) {
  final byTime = a.hostTimestampMicros.compareTo(b.hostTimestampMicros);
  return byTime != 0 ? byTime : a.playerId.compareTo(b.playerId);
}

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
        'shortAnswer' => ShortAnswer.fromJson(json),
        'ordering' => OrderingAnswer.fromJson(json),
        'matching' => MatchingAnswer.fromJson(json),
        'estimation' => EstimationAnswer.fromJson(json),
        'location' => LocationAnswer.fromJson(json),
        'trueFalse' => TrueFalseAnswer.fromJson(json),
        VerbalAnswer._kind => VerbalAnswer.fromJson(json),
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
    this.optionId = '',
    this.optionIds,
  });

  /// Restores the submission from [json].
  factory MultipleChoiceAnswer.fromJson(JsonMap json) => MultipleChoiceAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    optionId: json.readStringOrNull('optionId') ?? '',
    optionIds: json['optionIds'] == null
        ? null
        : json.readStringList('optionIds'),
  );

  static const String _kind = 'multipleChoice';

  /// Identifier of the chosen option.
  final String optionId;
  final List<String>? optionIds;
  List<String> get selectedOptionIds => optionIds ?? [optionId];

  @override
  MultipleChoiceAnswer withPlayerId(String id) => MultipleChoiceAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    optionId: optionId,
    optionIds: optionIds,
  );

  @override
  JsonMap toJson() => {
    ...baseJson(_kind),
    'optionId': optionId,
    if (optionIds != null) 'optionIds': optionIds,
  };

  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    optionId,
    optionIds,
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

final class ShortAnswer extends AnswerSubmission {
  const ShortAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.text,
  });
  final String text;
  factory ShortAnswer.fromJson(JsonMap json) => ShortAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    text: json.readString('text'),
  );
  @override
  ShortAnswer withPlayerId(String id) => ShortAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    text: text,
  );
  @override
  JsonMap toJson() => {...baseJson('shortAnswer'), 'text': text};
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    text,
  ];
}

final class OrderingAnswer extends AnswerSubmission {
  const OrderingAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.itemIds,
  });
  final List<String> itemIds;
  factory OrderingAnswer.fromJson(JsonMap json) => OrderingAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    itemIds: json.readStringList('itemIds'),
  );
  @override
  OrderingAnswer withPlayerId(String id) => OrderingAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    itemIds: itemIds,
  );
  @override
  JsonMap toJson() => {...baseJson('ordering'), 'itemIds': itemIds};
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    itemIds,
  ];
}

final class MatchingAnswer extends AnswerSubmission {
  const MatchingAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.pairs,
  });
  final Map<String, String> pairs;
  factory MatchingAnswer.fromJson(JsonMap json) => MatchingAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    pairs: readStringMap(json, 'pairs'),
  );
  @override
  MatchingAnswer withPlayerId(String id) => MatchingAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    pairs: pairs,
  );
  @override
  JsonMap toJson() => {...baseJson('matching'), 'pairs': pairs};
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    pairs,
  ];
}

final class EstimationAnswer extends AnswerSubmission {
  const EstimationAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.value,
  });
  final double value;
  factory EstimationAnswer.fromJson(JsonMap json) => EstimationAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    value: readFiniteDouble(json, 'value'),
  );
  @override
  EstimationAnswer withPlayerId(String id) => EstimationAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    value: value,
  );
  @override
  JsonMap toJson() => {...baseJson('estimation'), 'value': value};
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    value,
  ];
}

/// A place marked on the map.
final class LocationAnswer extends AnswerSubmission {
  const LocationAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.latitude,
    required this.longitude,
  });
  final double latitude;
  final double longitude;
  factory LocationAnswer.fromJson(JsonMap json) => LocationAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    latitude: readFiniteDouble(json, 'latitude'),
    longitude: readFiniteDouble(json, 'longitude'),
  );
  @override
  LocationAnswer withPlayerId(String id) => LocationAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    latitude: latitude,
    longitude: longitude,
  );
  @override
  JsonMap toJson() => {
    ...baseJson('location'),
    'latitude': latitude,
    'longitude': longitude,
  };
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    latitude,
    longitude,
  ];
}

final class TrueFalseAnswer extends AnswerSubmission {
  const TrueFalseAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    required super.clockOffsetMicros,
    required this.value,
  });
  final bool value;
  factory TrueFalseAnswer.fromJson(JsonMap json) => TrueFalseAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
    value: readRequiredBool(json, 'value'),
  );
  @override
  TrueFalseAnswer withPlayerId(String id) => TrueFalseAnswer(
    playerId: id,
    questionId: questionId,
    clientTimestampMicros: clientTimestampMicros,
    clockOffsetMicros: clockOffsetMicros,
    value: value,
  );
  @override
  JsonMap toJson() => {...baseJson('trueFalse'), 'value': value};
  @override
  List<Object?> get props => [
    playerId,
    questionId,
    clientTimestampMicros,
    clockOffsetMicros,
    value,
  ];
}

/// An answer the player gave aloud; the host recorded it while judging.
///
/// Only the engine creates it (verbal answer mode, see `RoundState.verbal`):
/// no question accepts it as a client submission, so a player can never send
/// one. It carries no content, the host's verdict decides the points.
final class VerbalAnswer extends AnswerSubmission {
  const VerbalAnswer({
    required super.playerId,
    required super.questionId,
    required super.clientTimestampMicros,
    super.clockOffsetMicros = 0,
  });

  factory VerbalAnswer.fromJson(JsonMap json) => VerbalAnswer(
    playerId: json.readString('playerId'),
    questionId: json.readString('questionId'),
    clientTimestampMicros: json.readInt('clientTimestampMicros'),
    clockOffsetMicros: json.readInt('clockOffsetMicros'),
  );

  static const String _kind = 'verbal';

  @override
  VerbalAnswer withPlayerId(String id) => VerbalAnswer(
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
