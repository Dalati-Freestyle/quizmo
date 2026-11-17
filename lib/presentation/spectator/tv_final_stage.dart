/// The TV end screen with the final standings.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/game_protocol.dart';
import '../l10n/app_localizations.dart';

/// Final standings for the 1920×1080 TV canvas.
///
/// Shows at most [rowsPerPage] rows at once and pages through longer lists
/// automatically, because nobody operates the TV.
class TvFinalStage extends StatefulWidget {
  /// Creates the stage.
  const TvFinalStage({
    required this.protocol,
    this.review,
    this.rowsPerPage = 8,
    this.pageDuration = const Duration(seconds: 10),
    super.key,
  });

  /// Protocol of the finished game.
  final GameProtocol protocol;

  /// Optional final solution overview shown next to the standings.
  final Widget? review;

  /// Maximum number of leaderboard rows on screen.
  final int rowsPerPage;

  /// How long one page of a long leaderboard stays visible.
  final Duration pageDuration;

  @override
  State<TvFinalStage> createState() => _TvFinalStageState();
}

class _TvFinalStageState extends State<TvFinalStage> {
  int _page = 0;
  Timer? _timer;

  int get _pages => (widget.protocol.standings.length / widget.rowsPerPage)
      .ceil()
      .clamp(1, 1 << 20);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pageDuration, (_) {
      if (_pages > 1) setState(() => _page = (_page + 1) % _pages);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final protocol = widget.protocol;
    final page = _page % _pages;
    final rows = protocol.standings
        .skip(page * widget.rowsPerPage)
        .take(widget.rowsPerPage)
        .toList();
    final unit = protocol.usesChips
        ? context.tr('Chips')
        : context.tr('Punkte');
    final standings = Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, size: 56, color: scheme.primary),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  context.tr('Endstand'),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_pages > 1)
                Text(
                  context.tr('Seite {0} von {1}', [page + 1, _pages]),
                  style: TextStyle(
                    fontSize: 28,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(
              context.tr('No scores yet.'),
              style: const TextStyle(fontSize: 32),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  for (final standing in rows)
                    SizedBox(
                      height: constraints.maxHeight / widget.rowsPerPage,
                      child: _row(context, standing, unit),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final review = widget.review;
    if (review == null) return standings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: standings),
        const SizedBox(width: 40),
        Expanded(child: review),
      ],
    );
  }

  Widget _row(BuildContext context, ProtocolStanding standing, String unit) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('tv-final-${standing.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: standing.place == 1
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '${standing.place}.',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  standing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (standing.memberNames.isNotEmpty)
                  Text(
                    standing.memberNames.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${standing.score} $unit',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
