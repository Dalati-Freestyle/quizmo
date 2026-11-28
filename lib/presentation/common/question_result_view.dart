import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../core/engine/answer_evaluation.dart';
import '../../core/engine/geo.dart';
import '../../core/models/models.dart';
import 'snowflake_result_view.dart';

class QuestionResultView extends StatelessWidget {
  const QuestionResultView({
    required this.question,
    required this.game,
    this.host = false,
    this.tv = false,
    super.key,
  });
  final Question question;
  final GameState game;
  final bool host;

  /// On the TV the instruction replaces the kind, and lists are mixed so
  /// that they never look like the solution.
  final bool tv;
  @override
  Widget build(BuildContext context) {
    final revealed =
        game.round.status == RoundStatus.revealed &&
        (host || !game.resultsHidden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!tv)
          Text(
            context.tr(question.kindLabel),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        if (question.requiresManualGrading && !host && !revealed && !tv)
          Text(
            context.tr('Der Spielleiter bewertet die Antworten.'),
            style: const TextStyle(fontSize: 22),
          ),
        if (question case MultipleChoiceQuestion(
          :final options,
          :final solutionOptionIds,
        ))
          for (final option in options)
            Text(
              '${revealed && solutionOptionIds.contains(option.id) ? '✓ ' : '• '}${option.label}',
              style: const TextStyle(fontSize: 24),
            ),
        if (question case final OrderingQuestion ordering)
          for (final item in ordering.displayItems)
            Text('• ${item.label}', style: const TextStyle(fontSize: 24)),
        if (question case final MatchingQuestion matching)
          if (tv)
            Row(
              key: const ValueKey('tv-matching-lists'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (side, items) in [
                  ('a', matching.displayLeftItems),
                  ('b', matching.displayRightItems),
                ]) ...[
                  if (side == 'b') const SizedBox(width: 32),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in items)
                              Text(
                                '• ${item.label}',
                                style: const TextStyle(fontSize: 24),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else
            for (final (i, left) in matching.displayLeftItems.indexed)
              Text(
                '${left.label}    |    ${i < matching.rightItems.length ? matching.displayRightItems[i].label : ''}',
                style: const TextStyle(fontSize: 24),
              ),
        if ((host || revealed) && game.round.snowflake != null) ...[
          const SizedBox(height: 12),
          SnowflakeResultView(game: game, maxGroups: host ? 50 : 8),
        ] else if (host || revealed) ...[
          const SizedBox(height: 12),
          Text(
            context.tr("Lösung: {0}", [
              question is TrueFalseQuestion
                  ? context.tr(question.solutionLabel)
                  : question.solutionLabel,
            ]),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          for (final answer in game.round.answers.values.take(
            host ? 50 : 8,
          )) ...[
            Text(
              '${game.players[answer.playerId]?.name ?? answer.playerId}: ${answerLabel(answer, question, context: context)}',
              style: const TextStyle(fontSize: 22),
            ),
            if (revealed && question.requiresManualGrading)
              Text(
                context.tr(
                  game.round.answerVerdicts[answer.playerId] == 1
                      ? 'Richtig'
                      : 'Wrong',
                ),
                style: const TextStyle(fontSize: 22),
              ),
          ],
        ],
        const SizedBox(height: 12),
        Text(
          answerProgressText(context, game),
          style: const TextStyle(fontSize: 22),
        ),
      ],
    );
  }
}

/// "3 / 5 Antworten", or "3 / 3 Teams" when every team counts as one
/// answer; [sentence] gives "3 von 3 Teams haben geantwortet".
String answerProgressText(
  BuildContext context,
  GameState game, {
  bool sentence = false,
}) {
  final (:answered, :expected, :teams) = game.answerProgress;
  return context.tr(
    switch ((sentence, teams)) {
      (false, false) => "{0} / {1} Antworten",
      (false, true) => "{0} / {1} Teams",
      (true, false) => "{0} of {1} answered",
      (true, true) => "{0} von {1} Teams haben geantwortet",
    },
    [answered, expected],
  );
}

/// "C · Indonesien" for the option [optionId] of [question]: letter and
/// text, as on the TV; never the internal ID while the option exists.
String choiceLabel(MultipleChoiceQuestion question, String optionId) {
  final index = question.options.indexWhere((o) => o.id == optionId);
  return index < 0
      ? optionId
      : '${String.fromCharCode(0x41 + index)} · ${question.options[index].label}';
}

String answerLabel(
  AnswerSubmission answer,
  Question question, {
  BuildContext? context,
}) => switch (answer) {
  ShortAnswer(:final text) => text,
  EstimationAnswer(:final value) =>
    question is EstimationQuestion
        ? [
            question.valueLabel(value),
            // Only known after the reveal, like the distance on a map.
            ?question.deviationLabel(value),
          ].join(' · ')
        : formatNumber(value),
  LocationAnswer(:final latitude, :final longitude) => [
    GeoPoint(latitude, longitude).label,
    if (question case final LocationQuestion location)
      if (location.distanceOf(answer) case final km?) formatDistance(km),
  ].join(' · '),
  TrueFalseAnswer(:final value) =>
    value
        ? (context?.tr("Wahr") ?? 'Wahr')
        : (context?.tr("Falsch") ?? 'Falsch'),
  OrderingAnswer(:final itemIds) =>
    question is OrderingQuestion
        ? itemIds
              .map(
                (id) =>
                    question.items
                        .where((i) => i.id == id)
                        .firstOrNull
                        ?.label ??
                    id,
              )
              .join(' → ')
        : itemIds.join(', '),
  MatchingAnswer(:final pairs) =>
    question is MatchingQuestion
        ? pairs.entries
              .map(
                (e) =>
                    '${question.leftItems.where((i) => i.id == e.key).firstOrNull?.label ?? e.key} → ${question.rightItems.where((i) => i.id == e.value).firstOrNull?.label ?? e.value}',
              )
              .join(', ')
        : pairs.toString(),
  MultipleChoiceAnswer(:final selectedOptionIds) =>
    selectedOptionIds
        .map(
          (id) => question is MultipleChoiceQuestion
              ? choiceLabel(question, id)
              : id,
        )
        .join(', '),
  BuzzerPress() => context?.tr("Buzzer") ?? 'Buzzer',
  VerbalAnswer() =>
    context?.tr("Mündlich beantwortet") ?? 'Mündlich beantwortet',
};
