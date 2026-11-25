/// Lets a team (or the host for a team) play a joker in the question on stage.
library;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';
import 'joker_texts.dart';

/// Called with the joker, the playing team and the target team, if any.
typedef JokerUseCallback = void Function(
  String jokerId,
  String teamId,
  String? targetTeamId,
);

/// Buttons for every joker of the session.
///
/// With [teamId] the form plays for that team (a player's own team);
/// without, the host first picks the team. Rules mirror the engine, which
/// validates every play again.
class JokerPlayForm extends StatefulWidget {
  /// Creates the form for [game].
  const JokerPlayForm({
    required this.game,
    required this.onUse,
    this.teamId,
    super.key,
  });

  final GameState game;
  final String? teamId;
  final JokerUseCallback onUse;

  @override
  State<JokerPlayForm> createState() => _JokerPlayFormState();
}

class _JokerPlayFormState extends State<JokerPlayForm> {
  String? _team;
  final Map<String, String?> _targets = {};

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final jokers = game.jokers;
    final poker = game.poker;
    if (jokers == null ||
        !jokers.jokers.any(
          (joker) => joker.beforeReveal == (poker?.questionHidden ?? false),
        )) {
      return const SizedBox.shrink();
    }
    final teamId = widget.teamId ?? _team;
    final betting = poker?.betting ?? false;
    final involved = teamId != null && jokers.involves(teamId);
    bool hasChips(String id) => poker == null || poker.availableFor(id) > 0;
    final targets = [
      for (final team in game.teams.values)
        if (team.id != teamId && !jokers.involves(team.id) && hasChips(team.id))
          team,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.teamId == null)
          DropdownButtonFormField<String>(
            key: const ValueKey('joker-team'),
            initialValue: _team,
            decoration: InputDecoration(
              labelText: context.tr("Joker spielen für"),
            ),
            items: [
              for (final team in game.teams.values)
                DropdownMenuItem(value: team.id, child: Text(team.name)),
            ],
            onChanged: (value) => setState(() => _team = value),
          ),
        if (involved)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              context.tr(
                "Dieses Team ist in dieser Frage schon von einem Joker betroffen.",
              ),
            ),
          ),
        // Only the jokers of the current phase: before the reveal the attack,
        // afterwards the defensive ones.
        for (final joker in jokers.jokers)
          if (joker.beforeReveal == (poker?.questionHidden ?? false))
            Builder(
              builder: (context) {
                final remaining = teamId == null
                    ? 0
                    : jokers.remainingFor(teamId, joker);
                final target = _targets[joker.id];
                final validTarget =
                    !joker.needsTarget || targets.any((t) => t.id == target);
                final payable = switch (joker) {
                  CreditJoker() => teamId != null && hasChips(teamId),
                  ForcedStakeJoker(:final cost) =>
                    teamId != null && (poker?.chips[teamId] ?? 0) >= cost,
                };
                final enabled =
                    betting &&
                    teamId != null &&
                    !involved &&
                    remaining > 0 &&
                    payable &&
                    validTarget;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (joker.needsTarget && remaining > 0 && !involved)
                        DropdownButtonFormField<String>(
                          key: ValueKey('joker-target-${joker.id}'),
                          initialValue: targets.any((t) => t.id == target)
                              ? target
                              : null,
                          decoration: InputDecoration(
                            labelText: context.tr("Angegriffenes Team"),
                          ),
                          items: [
                            for (final team in targets)
                              DropdownMenuItem(
                                value: team.id,
                                child: Text(team.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _targets[joker.id] = value),
                        ),
                      OutlinedButton.icon(
                        key: ValueKey('joker-play-${joker.id}'),
                        icon: Icon(jokerIcon(joker)),
                        onPressed: enabled
                            ? () => widget.onUse(
                                joker.id,
                                teamId,
                                joker.needsTarget ? target : null,
                              )
                            : null,
                        label: Text(
                          context.tr("{0} spielen ({1} übrig)", [
                            jokerName(context, joker),
                            remaining < 0 ? 0 : remaining,
                          ]),
                        ),
                      ),
                      Text(
                        jokerRule(context, joker),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
      ],
    );
  }
}
