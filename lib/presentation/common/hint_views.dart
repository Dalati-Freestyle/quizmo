/// Hints of the question on stage, shared by the host, player and TV views.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';
import 'question_media_view.dart';
import 'media_playback.dart';
import 'quiz_markdown.dart';

/// Whether [hint] has media that plays (audio or video).
bool hintPlaysMedia(QuestionHint hint) => hint.media.any(
  (media) => media is AudioAttachment || media is VideoAttachment,
);

/// Whether the hint shown last plays media; the question's own media then
/// stays silent so both cannot be heard at the same time.
bool latestHintPlays(RoundState round) =>
    round.status != RoundStatus.revealed &&
    round.shownHints.isNotEmpty &&
    hintPlaysMedia(round.shownHints.last);

/// How many hints are shown, what the next one costs and how many points are
/// left; `null` without hints.
String? hintStatusText(BuildContext context, GameState game) {
  final round = game.round;
  final total = round.question?.hints.length ?? 0;
  if (total == 0) return null;
  final costly =
      game.hintsCostPoints && round.question!.hints.any((h) => h.cost > 0);
  return [
    context.tr('Tipps: {0} von {1}', [round.shownHintCount, total]),
    if (costly) ...[
      if (round.nextHint case final next?)
        next.cost > 0
            ? context.tr('nächster Tipp: −{0} Punkte', [next.cost])
            : context.tr('nächster Tipp: kostenlos'),
      if (game.reachablePoints case final points?)
        context.tr('noch bis zu {0} Punkte', [points]),
    ],
  ].join(' · ');
}

/// "Hint 2 (−3 points)".
String hintTitle(BuildContext context, GameState game, int index) {
  final cost = game.round.question!.hints[index].cost;
  final title = context.tr('Tipp {0}', [index + 1]);
  return game.hintsCostPoints && cost > 0
      ? '$title (${context.tr('−{0} Punkte', [cost])})'
      : title;
}

/// The shown hints on a player device, plus how many are left.
class PlayerHintsView extends StatelessWidget {
  /// Creates the view for the round on stage of [game].
  const PlayerHintsView({required this.game, this.baseUri, super.key});

  final GameState game;
  final Uri? baseUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final round = game.round;
    final revealed = round.status == RoundStatus.revealed;
    final status = hintStatusText(context, game);
    final shown = round.shownHints;
    if (status == null || (revealed && shown.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const ValueKey('player-hints'),
      margin: const EdgeInsets.only(top: 16),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    revealed ? context.tr('Gezeigte Tipps') : status,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            for (final (index, hint) in shown.indexed) ...[
              const SizedBox(height: 12),
              Text(
                hintTitle(context, game, index),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
              if (!isBlankMarkdown(hint.text))
                QuizMarkdown(hint.text, style: theme.textTheme.bodyLarge),
              if (hint.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                QuestionMediaView(
                  key: ValueKey('hint-media-$index'),
                  media: hint.media,
                  baseUri: baseUri,
                  // Only the newest hint follows the host's media controls.
                  playback: MediaPlayback.onDevice(
                    game,
                    stopped: revealed || index < shown.length - 1,
                  ),
                  playbackRevision: game.tvMediaRevision,
                  commandRevision: game.tvMediaCommandRevision,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
