import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';
import 'question_media_view.dart';
import 'question_result_view.dart';

class QuizReviewView extends StatelessWidget {
  const QuizReviewView({
    required this.game,
    required this.playerId,
    this.mediaBaseUri,
    super.key,
  });

  final GameState game;
  final String? playerId;
  final Uri? mediaBaseUri;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('Quiz-Auflösung'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(context.tr('Alle Fragen und Lösungen im Überblick.')),
      if (game.players[playerId] case final player?) ...[
        const SizedBox(height: 8),
        Text(
          context.tr('Dein Punktestand: {0}', [
            game.mode is TeamMode
                ? game.teamScores[player.teamId] ?? 0
                : game.scores.scoreOf(player.id),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      for (final (index, round) in game.roundHistory.indexed)
        if (round.question case final question?)
          Card(
            child: ExpansionTile(
              key: ValueKey('review-$index'),
              title: Text('${index + 1}. ${question.prompt}'),
              subtitle: Text(
                context.tr('Lösung: {0}', [
                  question is TrueFalseQuestion
                      ? context.tr(question.solutionLabel)
                      : question.solutionLabel,
                ]),
              ),
              childrenPadding: const EdgeInsets.all(16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (round.answers[playerId] case final answer?) ...[
                  Text(
                    context.tr('Deine Antwort: {0}', [
                      answerLabel(answer, question, context: context),
                    ]),
                  ),
                  Text(
                    context.tr(switch (round.accuracyFor(answer)) {
                      1 => 'Richtig!',
                      final double accuracy when accuracy > 0 =>
                        'Teilweise richtig',
                      _ => 'Leider falsch',
                    }),
                  ),
                ] else if (round.buzzerVerdicts[playerId] case final verdict?)
                  Text(context.tr(verdict == 1 ? 'Richtig!' : 'Leider falsch'))
                else
                  Text(context.tr('Keine Antwort')),
                QuestionMediaView(
                  media: question.media,
                  baseUri: mediaBaseUri,
                  playing: false,
                ),
                QuestionMediaView(
                  media: question.solutionMedia,
                  baseUri: mediaBaseUri,
                  playing: false,
                ),
              ],
            ),
          ),
    ],
  );
}
