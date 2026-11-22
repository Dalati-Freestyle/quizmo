/// Changes the framing settings of many questions at once (quiz editor).
library;

import '../engine/scoring_rules.dart';
import 'json.dart';
import 'media_attachment.dart';
import 'question.dart';

/// The settings around a question – everything except its text, answers and
/// solution – applied to several questions in one go.
///
/// Every field left `null` stays as it is on each question, so a bulk edit
/// never wipes individual settings it was not asked to change, and every
/// question can still be adjusted on its own afterwards.
final class QuestionBulkEdit {
  /// Creates a bulk edit; `null` fields are left unchanged.
  const QuestionBulkEdit({
    this.timeLimit,
    this.softTimeLimit,
    this.category,
    this.scoringRule,
    this.hideQuestionMediaDetails,
    this.hideSolutionMediaDetails,
    this.imageZoom,
    this.manualGrading,
    this.maxEdits,
    this.lockOutOnMiss,
    this.hostEndsRound,
  });

  /// New time limit; [Duration.zero] removes it.
  final Duration? timeLimit;

  /// Soft (`true`) or hard (`false`) limit; ignored without a time limit.
  final bool? softTimeLimit;

  /// New category; an empty string removes it.
  final String? category;

  /// New scoring rule.
  final ScoringRule? scoringRule;

  /// Hide captions and titles of the question media on player and TV devices.
  final bool? hideQuestionMediaDetails;

  /// Hide captions and titles of the solution media.
  final bool? hideSolutionMediaDetails;

  /// Whether pictures can be enlarged with a tap.
  final bool? imageZoom;

  /// Free text answers: judged by the host instead of automatically.
  final bool? manualGrading;

  /// Free text answers: allowed typos (0–5).
  final int? maxEdits;

  /// Buzzer: a player who missed may not buzz again.
  final bool? lockOutOnMiss;

  /// Buzzer: the host ends the round instead of the first correct answer.
  final bool? hostEndsRound;

  /// Whether the edit changes anything at all.
  bool get isEmpty => [
    timeLimit,
    softTimeLimit,
    category,
    scoringRule,
    hideQuestionMediaDetails,
    hideSolutionMediaDetails,
    imageZoom,
    manualGrading,
    maxEdits,
    lockOutOnMiss,
    hostEndsRound,
  ].every((value) => value == null);

  /// Returns [question] with this edit applied.
  Question apply(Question question) {
    final json = question.toJson();
    final limit = timeLimit ?? question.timeLimit;
    // Kind specific settings: an exhaustive match over the sealed hierarchy,
    // so a new kind decides which of them it supports.
    final JsonMap specific = switch (question) {
      ShortAnswerQuestion() => {
        if (manualGrading != null) 'manualGrading': manualGrading,
        if (maxEdits != null) 'maxEdits': maxEdits,
      },
      BuzzerQuestion() => {
        if (lockOutOnMiss != null) 'lockOutOnMiss': lockOutOnMiss,
        if (hostEndsRound != null) 'hostEndsRound': hostEndsRound,
      },
      MultipleChoiceQuestion() ||
      OrderingQuestion() ||
      MatchingQuestion() ||
      EstimationQuestion() ||
      TrueFalseQuestion() => const {},
    };
    return Question.fromJson({
      ...json,
      ...specific,
      'timeLimitMs': limit.inMilliseconds,
      // A soft limit needs a limit at all.
      'softTimeLimit':
          limit > Duration.zero && (softTimeLimit ?? question.softTimeLimit),
      if (category != null)
        'category': category!.trim().isEmpty ? null : category!.trim(),
      if (scoringRule != null) 'scoringRule': scoringRule!.toJson(),
      'media': [
        for (final media in question.media)
          _media(media, hideQuestionMediaDetails).toJson(),
      ],
      'solutionMedia': [
        for (final media in question.solutionMedia)
          _media(media, hideSolutionMediaDetails).toJson(),
      ],
    });
  }

  MediaAttachment _media(MediaAttachment media, bool? hide) {
    var result = hide == null ? media : media.withHiddenDetails(hide);
    if (imageZoom case final zoom? when result is ImageAttachment) {
      result = MediaAttachment.fromJson({...result.toJson(), 'zoom': zoom});
    }
    return result;
  }
}
