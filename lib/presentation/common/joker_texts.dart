/// Names, rules and play summaries of jokers, shared by editor, host,
/// player and TV views.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';

/// Every joker kind the editor offers, with its default configuration.
///
/// A new kind is added here; the editor only offers the kinds that
/// `Joker.isSupportedBy` the quiz format.
const List<Joker> kJokerTemplates = [CreditJoker(), ForcedStakeJoker()];

/// Display name of [joker].
String jokerName(BuildContext context, Joker joker) => switch (joker) {
  CreditJoker() => context.tr("Kredit-Joker"),
  ForcedStakeJoker() => context.tr("Angriffs-Joker (Zwangseinsatz)"),
};

/// Icon of [joker].
IconData jokerIcon(Joker joker) => switch (joker) {
  CreditJoker() => Icons.shield_outlined,
  ForcedStakeJoker() => Icons.flash_on_outlined,
};

/// One-sentence rule of [joker] with its configured numbers.
String jokerRule(BuildContext context, Joker joker) => switch (joker) {
  CreditJoker(:final maxLoss) => context.tr(
    "Geht der Einsatz verloren, trägt die Bank den Verlust bis auf {0} Chip(s). In der Einsatzphase spielen.",
    [maxLoss],
  ),
  ForcedStakeJoker(:final stake, :final cost, :final lossFactor) => context.tr(
    "Euer Team zwingt ein anderes Team, genau {0} Chips zu setzen (hat es weniger, geht es all-in). Antwortet es richtig, gibt es die übliche Auszahlung; antwortet es falsch, verliert es das {1}-Fache des Einsatzes. Der Angriff kostet euer Team {2} Chips. Nur in der Einsatzphase spielbar.",
    [stake, lossFactor, cost],
  ),
};

/// Describes the joker plays of the question on stage, one line each.
List<String> jokerPlayLines(BuildContext context, GameState game) {
  final jokers = game.jokers;
  if (jokers == null) return const [];
  String team(String? id) => game.teams[id]?.name ?? id ?? '?';
  return [
    for (final play in jokers.plays)
      if (jokers.jokerById(play.jokerId) case final joker?)
        switch (joker) {
          CreditJoker() => context.tr("{0} spielt den Kredit-Joker.", [
            team(play.teamId),
          ]),
          ForcedStakeJoker() => context.tr(
            "{0} greift {1} an: Zwangseinsatz {2} Chips.",
            [
              team(play.teamId),
              team(play.targetTeamId),
              game.poker?.wagers[play.targetTeamId] ?? 0,
            ],
          ),
        },
  ];
}
