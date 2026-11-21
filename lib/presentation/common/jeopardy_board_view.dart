/// The Jeopardy board: category headers above a grid of point cells.
///
/// One widget serves three audiences, only the [JeopardyBoardStyle] differs:
/// the quizmaster (tappable cells, Daily Doubles marked), the players' phones
/// (shrinks to the screen width, scrolls sideways only below
/// [JeopardyBoardStyle.minScale]) and
/// the TV (read-only, fills the whole stage with large type).
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../core/models/models.dart';

/// Sizing of a [JeopardyBoardView].
final class JeopardyBoardStyle {
  /// Creates a style.
  const JeopardyBoardStyle({
    required this.headerFontSize,
    required this.pointsFontSize,
    required this.headerHeight,
    required this.gap,
    this.cellHeight,
    this.minColumnWidth = 0,
    this.radius = 10,
    this.minScale = 0.6,
  });

  /// Phones and the host dashboard.
  static const JeopardyBoardStyle compact = JeopardyBoardStyle(
    headerFontSize: 12,
    pointsFontSize: 18,
    headerHeight: 52,
    gap: 6,
    cellHeight: 52,
    minColumnWidth: 92,
  );

  /// The 1920×1080 TV canvas; the cells share the available height.
  static const JeopardyBoardStyle tv = JeopardyBoardStyle(
    headerFontSize: 28,
    pointsFontSize: 56,
    headerHeight: 104,
    gap: 12,
    radius: 20,
  );

  /// Font size of the category names.
  final double headerFontSize;

  /// Font size of the point values.
  final double pointsFontSize;

  /// Height of the header row.
  final double headerHeight;

  /// Space between cells.
  final double gap;

  /// Fixed cell height, or `null` to share the available height equally.
  final double? cellHeight;

  /// Narrowest a column may get before the board scrolls sideways.
  final double minColumnWidth;

  /// Corner radius of headers and cells.
  final double radius;

  /// A board wider than the screen is scaled down to fit, text included,
  /// but not below this factor; beyond it the board scrolls sideways.
  final double minScale;
}

/// Renders [board] and marks which cells were already played.
class JeopardyBoardView extends StatelessWidget {
  /// Creates a board view.
  ///
  /// With [onSelect] the open cells are tappable. [showDailyDoubles] reveals
  /// the Daily Double cells and must stay `false` on every screen the players
  /// can see.
  const JeopardyBoardView({
    required this.board,
    required this.completedQuestionIds,
    this.onSelect,
    this.winners = const {},
    this.showDailyDoubles = false,
    this.highlightQuestionId,
    this.pendingQuestionId,
    this.style = JeopardyBoardStyle.compact,
    super.key,
  });

  /// Layout and point values.
  final JeopardyBoard board;
  final Map<String, String> winners;

  /// Questions that were played; their point values remain visible but disabled.
  final Set<String> completedQuestionIds;

  /// Called with the question id of a tapped, still open cell.
  final ValueChanged<String>? onSelect;

  /// Whether Daily Double cells are marked with a star.
  final bool showDailyDoubles;

  /// Cell to emphasise, for example a Daily Double waiting for its wager.
  final String? highlightQuestionId;

  /// Cell a player picked that waits for the host's confirmation.
  final String? pendingQuestionId;

  /// Sizing.
  final JeopardyBoardStyle style;

  @override
  Widget build(BuildContext context) {
    if (board.categories.isEmpty || board.rowCount == 0) {
      return const SizedBox.shrink();
    }

    final grid = Column(
      children: [
        SizedBox(height: style.headerHeight, child: _buildHeaders(context)),
        for (var row = 0; row < board.rowCount; row++) ...[
          SizedBox(height: style.gap),
          if (style.cellHeight case final height?)
            SizedBox(height: height, child: _buildRow(context, row))
          else
            Expanded(child: _buildRow(context, row)),
        ],
      ],
    );

    if (style.cellHeight == null) return grid;

    final height =
        style.headerHeight +
        board.rowCount * (style.gap + (style.cellHeight ?? 0));
    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = board.categories.length * style.minColumnWidth;
        if (!constraints.hasBoundedWidth || constraints.maxWidth >= needed) {
          return grid;
        }
        // Shrink the whole board (text included) so every column stays on
        // screen; only a board that would become unreadable scrolls.
        final scale = (constraints.maxWidth / needed).clamp(
          style.minScale,
          1.0,
        );
        final scaled = SizedBox(
          key: const ValueKey('jeopardy-board-scaled'),
          width: needed * scale,
          height: height * scale,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: needed, height: height, child: grid),
          ),
        );
        if (needed * scale <= constraints.maxWidth + 0.5) return scaled;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: scaled,
        );
      },
    );
  }

  Widget _buildHeaders(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        for (var index = 0; index < board.categories.length; index++) ...[
          if (index > 0) SizedBox(width: style.gap),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(style.radius),
              ),
              child: Text(
                board.categories[index].name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: style.headerFontSize,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, int row) => Row(
    children: [
      for (var index = 0; index < board.categories.length; index++) ...[
        if (index > 0) SizedBox(width: style.gap),
        Expanded(child: _buildCell(context, index, row)),
      ],
    ],
  );

  Widget _buildCell(BuildContext context, int category, int row) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cell = board.cellAt(category, row);
    final id = cell.questionId;
    final shape = BorderRadius.circular(style.radius);

    if (id == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: shape,
        ),
      );
    }

    final completed = completedQuestionIds.contains(id);
    final isHighlighted = id == highlightQuestionId;
    final isPending = !completed && id == pendingQuestionId;
    final points = row < board.rowPoints.length ? board.rowPoints[row] : 0;
    final label = Text(
      '$points',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontSize: style.pointsFontSize,
        fontWeight: FontWeight.w800,
        decoration: completed ? TextDecoration.lineThrough : null,
        color: completed
            ? scheme.outline
            : isHighlighted
            ? scheme.onTertiaryContainer
            : isPending
            ? scheme.onSecondary
            : scheme.onPrimaryContainer,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Material(
      color: completed
          ? scheme.surfaceContainerHighest
          : isHighlighted
          ? scheme.tertiaryContainer
          : isPending
          ? scheme.secondary
          : scheme.primaryContainer,
      shape: isPending
          ? RoundedRectangleBorder(
              borderRadius: shape,
              side: BorderSide(color: scheme.onSecondaryContainer, width: 3),
            )
          : null,
      borderRadius: isPending ? null : shape,
      child: InkWell(
        borderRadius: shape,
        onTap: completed || onSelect == null ? null : () => onSelect!(id),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                label,
                if (completed)
                  Text(
                    winners[id] ?? context.tr("Keine Punkte"),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: style == JeopardyBoardStyle.tv ? 22 : 11,
                      color: scheme.outline,
                    ),
                  ),
              ],
            ),
            if (isPending)
              Positioned(
                top: 2,
                right: 4,
                child: Icon(
                  Icons.hourglass_top,
                  size: style.pointsFontSize * 0.6,
                  color: scheme.onSecondary,
                ),
              )
            else if (!completed &&
                ((showDailyDoubles && cell.isDailyDouble) || isHighlighted))
              Positioned(
                top: 2,
                right: 4,
                child: Icon(
                  Icons.star,
                  size: style.pointsFontSize * 0.6,
                  color: scheme.tertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
