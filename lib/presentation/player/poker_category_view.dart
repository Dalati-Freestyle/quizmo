/// Category phase of a poker question on a player device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../common/joker_play_form.dart';
import '../common/joker_texts.dart';
import '../l10n/app_localizations.dart';
import 'player_page.dart';
import 'player_session_cubit.dart';

/// Shows only the category of the coming question: the question itself is
/// still hidden. Teams
/// decide on the jokers played before the reveal, and with category slides
/// they place their stakes on the category.
class PokerCategoryView extends StatelessWidget {
  /// Creates the view for [state].
  const PokerCategoryView({required this.state, super.key});

  final PlayerSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = state.game!;
    final poker = game.poker!;
    final category = poker.category;
    final team = state.me?.teamId;
    final cubit = context.read<PlayerSessionCubit>();
    final stakes = poker.stakesBeforeReveal && poker.betting;
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
            stakes
                ? "Die Frage ist noch verdeckt. Setzt jetzt auf die Kategorie; die Frage wird aufgedeckt, wenn der Spielleiter die Einsätze schließt."
                : "Die Frage ist noch verdeckt. Jetzt ist die Zeit für Angriffs-Joker; gesetzt wird erst nach dem Aufdecken.",
          ),
        ),
        const SizedBox(height: 16),
        if (stakes)
          // Stake form and every joker, as in the betting with a question.
          PokerWagerView(
            key: ValueKey('category-wager-${game.round.startedAtHostMicros}'),
            state: state,
            onWager: cubit.placePokerWager,
          )
        else ...[
          for (final line in jokerPlayLines(context, game))
            Text(line, style: theme.textTheme.titleSmall),
          if (team != null)
            JokerPlayForm(
              game: game,
              teamId: team,
              onUse: (jokerId, _, target) =>
                  cubit.useJoker(jokerId, targetTeamId: target),
            )
          else
            Text(context.tr("Der Quizmaster muss dich einem Team zuweisen.")),
        ],
      ],
    );
  }
}
