import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../core/models/models.dart';

class QuestionResultView extends StatelessWidget {
  const QuestionResultView({
    required this.question,
    required this.game,
    this.host = false,
    super.key,
  });
  final Question question;
  final GameState game;
  final bool host;
  @override
  Widget build(BuildContext context) {
    final revealed = game.round.status == RoundStatus.revealed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(question.kindLabel),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
        if (question case OrderingQuestion(:final items))
          for (final item in items)
            Text('• ${item.label}', style: const TextStyle(fontSize: 24)),
        if (question case MatchingQuestion(:final leftItems, :final rightItems))
          for (var i = 0; i < leftItems.length; i++)
            Text(
              '${leftItems[i].label}    |    ${i < rightItems.length ? rightItems[i].label : ''}',
              style: const TextStyle(fontSize: 24),
            ),
        if (host || revealed) ...[
          const SizedBox(height: 12),
          Text(
            context.tr("Lösung: {0}", [
              question is TrueFalseQuestion
                  ? context.tr(question.solutionLabel)
                  : question.solutionLabel,
            ]),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          for (final answer in game.round.answers.values.take(host ? 50 : 8))
            Text(
              '${game.players[answer.playerId]?.name ?? answer.playerId}: ${answerLabel(answer, question, context: context)}',
              style: const TextStyle(fontSize: 22),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          context.tr("{0} / {1} Antworten", [
            game.round.answers.length,
            game.connectedPlayers.length,
          ]),
          style: const TextStyle(fontSize: 22),
        ),
      ],
    );
  }
}

String answerLabel(
  AnswerSubmission answer,
  Question question, {
  BuildContext? context,
}) => switch (answer) {
  ShortAnswer(:final text) => text,
  EstimationAnswer(:final value) => '$value',
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
  MultipleChoiceAnswer(:final selectedOptionIds) => selectedOptionIds.join(
    ', ',
  ),
  BuzzerPress() => context?.tr("Buzzer") ?? 'Buzzer',
};
