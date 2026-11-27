/// TV stage for the category phase of a poker question.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../common/joker_texts.dart';
import '../l10n/app_localizations.dart';
import '../common/tv_instruction.dart';

/// Announces the category while the question is still hidden, together with
/// the attack jokers played so far.
class TvCategoryStage extends StatelessWidget {
  /// Creates the stage for [game].
  const TvCategoryStage({required this.game, super.key});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = game.poker?.category;
    final lines = jokerPlayLines(context, game);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr("Nächste Kategorie"),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            category == null || category.trim().isEmpty
                ? context.tr("Ohne Kategorie")
                : category,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 40),
          Text(
            [
              ?tvInstruction(context.tr, game)?.text,
              context.tr('Die Frage folgt gleich.'),
            ].join(' '),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 34, color: scheme.onSurfaceVariant),
          ),
          if (lines.isNotEmpty) const SizedBox(height: 32),
          for (final line in lines.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
