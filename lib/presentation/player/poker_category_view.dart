/// Category phase of a poker question on a player device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../common/joker_play_form.dart';
import '../common/joker_texts.dart';
import '../l10n/app_localizations.dart';
import 'player_session_cubit.dart';

/// Shows only the category of the coming question: the question itself is
/// still hidden, so teams decide on the jokers played before the reveal.
class PokerCategoryView extends StatelessWidget {
  /// Creates the view for [state].
  const PokerCategoryView({required this.state, super.key});

  final PlayerSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = state.game!;
    final category = game.poker?.category;
    final team = state.me?.teamId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr("Phase 1 · Kategorie"),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          category == null || category.trim().isEmpty
              ? context.tr("Ohne Kategorie")
              : category,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            "Die Frage ist noch verdeckt. Jetzt ist die Zeit für Angriffs-Joker; gesetzt wird erst nach dem Aufdecken.",
          ),
        ),
        const SizedBox(height: 16),
        for (final line in jokerPlayLines(context, game))
          Text(line, style: theme.textTheme.titleSmall),
        if (team != null)
          JokerPlayForm(
            game: game,
            teamId: team,
            onUse: (jokerId, _, target) => context
                .read<PlayerSessionCubit>()
                .useJoker(jokerId, targetTeamId: target),
          )
        else
          Text(context.tr("Der Quizmaster muss dich einem Team zuweisen.")),
      ],
    );
  }
}
