/// Interstitial slides: unscored screens between the questions
/// (quiz schema 12), e.g. a category title card, a break or "results are
/// coming".
library;

import 'package:equatable/equatable.dart';

import 'json.dart';
import 'media_attachment.dart';

/// A screen the host shows on the TV and the player devices between two
/// questions. It has no answers and no scoring.
final class InfoSlide extends Equatable {
  /// Creates a slide.
  const InfoSlide({
    required this.id,
    this.title = '',
    this.text = '',
    this.media = const [],
    this.beforeQuestionId,
    this.category,
  });

  /// Restores a slide from [json].
  factory InfoSlide.fromJson(JsonMap json) => InfoSlide(
    id: json.readString('id'),
    title: json.readString('title'),
    text: json.readString('text'),
    media: json.readList('media', MediaAttachment.fromJson),
    beforeQuestionId: json.readStringOrNull('beforeQuestionId'),
    category: normalizedCategory(json.readStringOrNull('category')),
  );

  /// Stable identifier inside the quiz.
  final String id;

  /// Large headline, e.g. "Trinkpause".
  final String title;

  /// Optional text below the headline.
  final String text;

  /// Pictures, videos or audio of the slide.
  final List<MediaAttachment> media;

  /// The slide is placed right before this question; `null` places it after
  /// the last question. Only decides the position in the editor and the
  /// host's question list; the host shows it whenever wanted.
  final String? beforeQuestionId;

  /// The category this slide introduces (quiz schema 19), `null` for an
  /// ordinary slide. With the host's "category slide before every question"
  /// it is shown before each question of the category, and in the category
  /// phase of Pokerchips its media accompany the category.
  final String? category;

  /// Whether this slide introduces [questionCategory].
  bool introduces(String? questionCategory) =>
      category != null && sameCategory(category, questionCategory);

  /// Problems of the slide; empty when it is valid.
  List<String> validationErrors(Set<String> questionIds) => [
    if (id.trim().isEmpty) 'Eine Zwischenfolie braucht eine ID.',
    if (title.trim().isEmpty && text.trim().isEmpty && media.isEmpty)
      'Eine Zwischenfolie braucht einen Titel, einen Text oder ein Medium.',
    if (beforeQuestionId != null && !questionIds.contains(beforeQuestionId))
      'Eine Zwischenfolie steht vor einer Frage, die es nicht gibt.',
    if (media.length > 10) 'Maximal zehn Medien pro Zwischenfolie.',
    for (final attachment in media) ...[
      ...attachment.validationErrors,
      if (attachment.asset != null && attachment.asset!.data == null)
        'Medien-Datei fehlt im Quiz.',
    ],
  ];

  /// Returns a copy with selected fields replaced.
  InfoSlide copyWith({
    String? title,
    String? text,
    List<MediaAttachment>? media,
    Object? beforeQuestionId = _unset,
    Object? category = _unset,
  }) => InfoSlide(
    id: id,
    title: title ?? this.title,
    text: text ?? this.text,
    media: media ?? this.media,
    beforeQuestionId: identical(beforeQuestionId, _unset)
        ? this.beforeQuestionId
        : beforeQuestionId as String?,
    category: identical(category, _unset)
        ? this.category
        : normalizedCategory(category as String?),
  );

  /// The copy that is sent to guests: media bytes only on request, hidden
  /// captions stripped.
  InfoSlide forWire({bool includeMediaData = false}) => InfoSlide.fromJson({
    ...toJson(),
    'media': media
        .map((attachment) => attachment.forWire(includeData: includeMediaData))
        .toList(growable: false),
  });

  /// Serializes the slide including its media.
  JsonMap toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'media': media.map((attachment) => attachment.toJson()).toList(),
    if (beforeQuestionId != null) 'beforeQuestionId': beforeQuestionId,
    if (category != null) 'category': category,
  };

  @override
  List<Object?> get props => [
    id,
    title,
    text,
    media,
    beforeQuestionId,
    category,
  ];
}

/// [category] without surrounding blanks; `null` when nothing is left.
String? normalizedCategory(String? category) {
  final trimmed = category?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Whether two categories are the same: blanks around them and the case of
/// the letters do not matter, a missing category matches nothing.
bool sameCategory(String? a, String? b) {
  final left = normalizedCategory(a);
  final right = normalizedCategory(b);
  return left != null &&
      right != null &&
      left.toLowerCase() == right.toLowerCase();
}

/// The slide of [slides] that introduces [category], if there is one.
InfoSlide? categorySlideOf(List<InfoSlide> slides, String? category) {
  for (final slide in slides) {
    if (slide.introduces(category)) return slide;
  }
  return null;
}

const Object _unset = Object();

/// [questions] in order with every slide placed before its question; slides
/// without a question (or with a missing one) come last.
List<Object> interleaveSlides<Q>(
  List<Q> questions,
  List<InfoSlide> slides,
  String Function(Q question) idOf,
) {
  final ids = questions.map(idOf).toSet();
  return [
    for (final question in questions) ...[
      for (final slide in slides)
        if (slide.beforeQuestionId == idOf(question)) slide,
      question as Object,
    ],
    for (final slide in slides)
      if (!ids.contains(slide.beforeQuestionId)) slide,
  ];
}
