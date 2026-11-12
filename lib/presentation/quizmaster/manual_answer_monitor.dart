import 'package:flutter/material.dart';

import '../../core/engine/answer_evaluation.dart';
import '../../core/engine/quiz_engine_event.dart';
import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

class ManualAnswerMonitor extends StatefulWidget {
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
  State<ManualAnswerMonitor> createState() => _ManualAnswerMonitorState();
}

class _ManualAnswerMonitorState extends State<ManualAnswerMonitor> {
  final _reason = TextEditingController();

  @override
  void didUpdateWidget(ManualAnswerMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.round.startedAtHostMicros !=
            widget.game.round.startedAtHostMicros ||
        oldWidget.question.id != widget.question.id) {
      _reason.clear();
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final question = widget.question;
    final onJudge = widget.onJudge;
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
          TextField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: context.tr('Grund (optional)'),
            ),
            enabled: canJudge,
          ),
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
                                ? (_) {
                                    onJudge(
                                      JudgeAnswerEvent(
                                        playerId: answer.playerId,
                                        questionId: question.id,
                                        startedAtHostMicros: startedAt,
                                        wasCorrect: correct,
                                        reason: _reason.text.trim(),
                                      ),
                                    );
                                    _reason.clear();
                                  }
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
