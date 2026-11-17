/// Result of a "Biggest Snowflake" round, shared by host, players and TV.
library;

import 'package:flutter/material.dart';

import '../../core/data/game_protocol_builder.dart';
import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// Lists the distinct answers of the round on stage, rarest first, with the
/// players who gave them and the share of the points they earn.
///
/// Renders nothing outside a snowflake round. Guests receive the answers only
/// with the reveal, so the list stays empty for them until then.
class SnowflakeResultView extends StatelessWidget {
  /// Creates the view for the round of [game].
  const SnowflakeResultView({
    required this.game,
    this.fontSize = 22,
    this.maxGroups = 8,
    super.key,
  });

  /// The (possibly redacted) snapshot.
  final GameState game;

  /// Text size; the TV needs at least 22 px.
  final double fontSize;

  /// Number of distinct answers listed at most.
  final int maxGroups;

  @override
  Widget build(BuildContext context) {
    final round = game.round;
    final question = round.question;
    if (question == null || round.snowflake == null) {
      return const SizedBox.shrink();
    }
    final groups = round.snowflakeGroups;
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: fontSize);
    final everyoneAgrees =
        groups.length == 1 && groups.single.playerIds.length > 1;

    String label(SnowflakeGroup group) {
      final answer = round.answers[group.playerIds.first]!;
      final text = protocolAnswerLabel(answer, question);
      // True/false answers are message keys, like `Question.solutionLabel`.
      return answer is TrueFalseAnswer ? context.tr(text) : text;
    }

    String names(SnowflakeGroup group) {
      final all = [
        for (final id in group.playerIds) game.players[id]?.name ?? id,
      ];
      const shown = 6;
      return [
        ...all.take(shown),
        if (all.length > shown) context.tr('+{0} more', [all.length - shown]),
      ].join(', ');
    }

    return Column(
      key: const ValueKey('snowflake-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Die seltenste Antwort gewinnt'),
          style: style.copyWith(fontWeight: FontWeight.bold),
        ),
        if (groups.isEmpty)
          Text(context.tr('Noch keine Antworten.'), style: style),
        if (everyoneAgrees)
          Text(
            context.tr('Alle haben gleich geantwortet – niemand punktet.'),
            style: style,
          ),
        for (final group in groups.take(maxGroups))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  group.share > 0 ? Icons.ac_unit : Icons.groups_outlined,
                  size: fontSize * 1.2,
                  color: group.share > 0
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                SizedBox(width: fontSize * 0.5),
                Expanded(
                  child: Text(
                    context.tr('{0} · {1}× · {2} % der Punkte\n{3}', [
                      label(group),
                      group.playerIds.length,
                      (group.share * 100).round(),
                      names(group),
                    ]),
                    style: style.copyWith(
                      fontWeight: group.share == 1 ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (groups.length > maxGroups)
          Text(
            context.tr('+{0} more', [groups.length - maxGroups]),
            style: style,
          ),
      ],
    );
  }
}
