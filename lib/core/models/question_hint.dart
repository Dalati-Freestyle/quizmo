/// Hints of a question (quiz schema 13) the host shows one after another.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';
import 'media_attachment.dart';

/// One hint of a question: text and/or media, optionally lowering the points
/// of every correct answer given after it was shown.
final class QuestionHint extends Equatable {
  /// Creates a hint.
  const QuestionHint({this.text = '', this.media = const [], this.cost = 0});

  /// Restores a hint from [json].
  factory QuestionHint.fromJson(JsonMap json) => QuestionHint(
    text: json.readStringOrNull('text') ?? '',
    media: readMedia(json, 'media'),
    cost: json.readIntOrNull('cost') ?? 0,
  );

  /// Most hints one question may have.
  static const int maxPerQuestion = 10;

  /// Largest [cost] of one hint.
  static const int maxCost = 1000000;

  /// What the guests read.
  final String text;

  /// Pictures, audio, videos, code or maps of the hint.
  final List<MediaAttachment> media;

  /// Points a correct answer earns less once the hint is shown; 0 for a free
  /// hint. Only reduces what the answer would have earned, never below 0.
  final int cost;

  /// Problems of the hint; empty when it is valid.
  List<String> get validationErrors => [
    if (text.trim().isEmpty && media.isEmpty)
      'Ein Tipp braucht einen Text oder ein Medium.',
    if (cost < 0 || cost > maxCost)
      'Der Punktabzug eines Tipps muss zwischen 0 und 1000000 liegen.',
    if (media.length > 10) 'Maximal zehn Medien pro Tipp.',
    for (final attachment in media) ...attachment.validationErrors,
  ];

  /// The copy a guest gets before the hint is shown: only its cost.
  QuestionHint concealed() => QuestionHint(cost: cost);

  /// The JSON sent to guests once the hint is shown.
  JsonMap forWire({bool includeMediaData = false}) => {
    ...toJson(),
    'media': [
      for (final attachment in media)
        attachment.forWire(includeData: includeMediaData),
    ],
  };

  /// Serializes the hint including its media.
  JsonMap toJson() => {
    'text': text,
    'media': media.map((attachment) => attachment.toJson()).toList(),
    'cost': cost,
  };

  @override
  List<Object?> get props => [text, media, cost];
}

/// Reads the optional hints of a question.
List<QuestionHint> readHints(JsonMap json) => json['hints'] == null
    ? const []
    : json.readList('hints', QuestionHint.fromJson);
