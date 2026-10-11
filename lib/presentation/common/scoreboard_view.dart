/// Shared score rendering for the host dashboard and the player screen.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../core/models/models.dart';

/// Renders solo or team standings, depending on [GameState.mode].
///
/// The aggregation is a pure domain concern, so this widget only decides *how*
/// to paint what `ScoreState` already computed.
class ScoreboardView extends StatelessWidget {
  /// Creates a scoreboard for [game].
  const ScoreboardView({
    required this.game,
    this.highlightPlayerId,
    this.maxEntries = 12,
    super.key,
  });

  /// The snapshot to render.
  final GameState game;

  /// Player rendered with an accent, typically "me".
  final String? highlightPlayerId;

  /// Maximum number of rows before the list is truncated.
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    if (game.poker != null) {
      return _TeamStandings(game: game, highlightPlayerId: highlightPlayerId);
    }
    return switch (game.mode) {
      TeamMode() => _TeamStandings(
        game: game,
        highlightPlayerId: highlightPlayerId,
      ),
      SoloMode() => _PlayerStandings(
        game: game,
        highlightPlayerId: highlightPlayerId,
        maxEntries: maxEntries,
      ),
    };
  }
}

class _PlayerStandings extends StatelessWidget {
  const _PlayerStandings({
    required this.game,
    required this.highlightPlayerId,
    required this.maxEntries,
  });

  final GameState game;
  final String? highlightPlayerId;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranking = game.scores.ranking
        .where((entry) => game.players.containsKey(entry.key))
        .take(maxEntries)
        .toList(growable: false);

    if (ranking.isEmpty) {
      return Text(
        context.tr("No scores yet."),
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      children: [
        for (var index = 0; index < ranking.length; index++)
          _ScoreRow(
            rank: index + 1,
            label: game.players[ranking[index].key]?.name ?? ranking[index].key,
            points: ranking[index].value,
            isHighlighted: ranking[index].key == highlightPlayerId,
            accent: _teamColor(game, ranking[index].key),
          ),
      ],
    );
  }

  Color? _teamColor(GameState game, String playerId) {
    final teamId = game.players[playerId]?.teamId;
    final team = teamId == null ? null : game.teams[teamId];
    return team == null ? null : Color(team.colorValue);
  }
}

class _TeamStandings extends StatelessWidget {
  const _TeamStandings({required this.game, required this.highlightPlayerId});

  final GameState game;
  final String? highlightPlayerId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = game.teamScores;
    if (game.teams.isEmpty) {
      return Text(
        context.tr("No teams configured."),
        style: theme.textTheme.bodySmall,
      );
    }

    final ordered = game.teams.values.toList(growable: false)
      ..sort((a, b) => (totals[b.id] ?? 0).compareTo(totals[a.id] ?? 0));
    final myTeamId = highlightPlayerId == null
        ? null
        : game.players[highlightPlayerId]?.teamId;

    return Column(
      children: [
        for (var index = 0; index < ordered.length; index++) ...[
          _ScoreRow(
            rank: index + 1,
            label: ordered[index].name,
            points: totals[ordered[index].id] ?? 0,
            isHighlighted: ordered[index].id == myTeamId,
            accent: Color(ordered[index].colorValue),
          ),
          for (final player in game.players.values.where(
            (player) => player.teamId == ordered[index].id,
          ))
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      player.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: player.isConnected
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.outline,
                        fontWeight: player.id == highlightPlayerId
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
                  Text(
                    '${game.scores.scoreOf(player.id)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.rank,
    required this.label,
    required this.points,
    required this.isHighlighted,
    this.accent,
  });

  final int rank;
  final String label;
  final int points;
  final bool isHighlighted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlighted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: accent == null
            ? null
            : Border(left: BorderSide(color: accent!, width: 4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank.', style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$points',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
