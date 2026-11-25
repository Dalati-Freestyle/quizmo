import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../common/question_result_view.dart';
import '../l10n/app_localizations.dart';
import 'player_session_cubit.dart';

/// Shows the answer that counts for the team, who sent it, and offers to send
/// the own answer again after somebody replaced it.
class TeamAnswerCard extends StatelessWidget {
  const TeamAnswerCard({
    required this.state,
    required this.onResend,
    super.key,
  });

  final PlayerSessionState state;

  /// Sends the own last answer again.
  final ValueChanged<AnswerSubmission> onResend;

  @override
  Widget build(BuildContext context) {
    final question = state.question;
    final answers = state.answers;
    final valid = answers?.valid;
    if (question == null ||
        answers == null ||
        valid == null ||
        !state.sharesTeamAnswer ||
        state.roundStatus == RoundStatus.revealed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = valid.playerId == state.playerId;
    final name = state.game?.players[valid.playerId]?.name ?? valid.playerId;
    final own = answers.own;
    final replaced = !mine && own != null && !sameAnswerContent(own, valid);
    return Card(
      key: const ValueKey('team-answer'),
      margin: const EdgeInsets.only(top: 16),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.groups),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr('Gültige Teamantwort: {0} (von {1})', [
                        answerLabel(valid, question, context: context),
                        mine ? context.tr('dir') : name,
                      ]),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            if (replaced) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('{0} hat die Teamantwort geändert.', [name]),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (answers.isFinal) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Die Spielleitung hat eure Antwort schon bewertet. Sie kann nicht mehr geändert werden.',
                ),
              ),
            ] else if (replaced && state.mayEditAnswer) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('resend-own-answer'),
                onPressed: () => onResend(own),
                icon: const Icon(Icons.replay),
                label: Text(context.tr('Meine Antwort wieder einsetzen')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
