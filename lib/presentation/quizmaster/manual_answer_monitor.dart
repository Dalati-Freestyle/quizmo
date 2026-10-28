import 'package:flutter/material.dart';

import '../../core/engine/answer_evaluation.dart';
import '../../core/engine/quiz_engine_event.dart';
import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

class ManualAnswerMonitor extends StatelessWidget {
  const ManualAnswerMonitor({
    required this.question,
    required this.game,
    required this.onJudge,
    super.key,
  });

  final ShortAnswerQuestion question;
  final GameState game;
  final ValueChanged<JudgeAnswerEvent>? onJudge;

  @override
  Widget build(BuildContext context) {
    final round = game.round;
    final revealed = round.status == RoundStatus.revealed;
    final startedAt = round.startedAtHostMicros;
    final canJudge = !revealed && startedAt != null && onJudge != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Manuelle Bewertung'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(context.tr('Lösung: {0}', [question.solutionLabel])),
        if (!revealed) ...[
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Die Empfehlungen sind unverbindlich. Bewerte jede eingegangene Antwort. Bis zur Auflösung kannst du deine Entscheidung ändern.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Noch {0} Antworten zu bewerten', [
              round.pendingGradeCount,
            ]),
          ),
        ],
        for (final answer in round.answers.values)
          if (answer is ShortAnswer)
            Card(
              key: ValueKey('manual-answer-${answer.playerId}'),
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      game.players[answer.playerId]?.name ?? answer.playerId,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SelectableText(answer.text),
                    const SizedBox(height: 8),
                    if (!revealed)
                      Text(
                        context.tr(switch (recommendTextAnswer(
                          answer.text,
                          question.acceptedAnswers ?? const [],
                          question.maxEdits,
                        )) {
                          TextAnswerRecommendation.exactMatch =>
                            'Empfehlung: Passt zur Lösung.',
                          TextAnswerRecommendation.possibleTypo => 'Empfehlung: Fast richtig, vermutlich ein Tippfehler.',
                          TextAnswerRecommendation.different => 'Empfehlung: Weicht von den hinterlegten Lösungen ab.',
                        }),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final correct in [true, false])
                          ChoiceChip(
                            label: Text(
                              context.tr(correct ? 'Richtig' : 'Wrong'),
                            ),
                            selected:
                                round.answerVerdicts[answer.playerId] ==
                                (correct ? 1 : 0),
                            onSelected: canJudge
                                ? (_) => onJudge!(
                                    JudgeAnswerEvent(
                                      playerId: answer.playerId,
                                      questionId: question.id,
                                      startedAtHostMicros: startedAt,
                                      wasCorrect: correct,
                                    ),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
