/// Responsive layout primitives shared by the host and the player shell.
///
/// The same widget tree has to work on a phone held in one hand and on a
/// browser window stretched across a 27" display, so every screen describes
/// itself as a list of panels and lets this file decide the column count.
library;

import 'package:flutter/material.dart';

/// Width classes used across the app.
enum FormFactor {
  /// Phones and narrow browser windows.
  compact,

  /// Tablets, split-screen desktop windows.
  medium,

  /// Full desktop and TV sized windows.
  expanded;

  /// Whether this class should render a multi column layout.
  bool get isWide => this != FormFactor.compact;
}

/// Breakpoints in logical pixels.
abstract final class Breakpoints {
  /// Upper bound of [FormFactor.compact].
  static const double compact = 720;

  /// Upper bound of [FormFactor.medium].
  static const double medium = 1180;
}

/// Returns the [FormFactor] for [width].
FormFactor formFactorForWidth(double width) {
  if (width < Breakpoints.compact) return FormFactor.compact;
  if (width < Breakpoints.medium) return FormFactor.medium;
  return FormFactor.expanded;
}

/// Returns the [FormFactor] of the nearest [MediaQuery].
FormFactor formFactorOf(BuildContext context) =>
    formFactorForWidth(MediaQuery.sizeOf(context).width);

/// Arranges [panels] into one, two or three scrolling columns.
///
/// Panels are distributed round robin, which keeps the visual weight balanced
/// without needing an intrinsic height pass.
class AdaptivePanelGrid extends StatelessWidget {
  /// Creates a panel grid.
  const AdaptivePanelGrid({
    required this.panels,
    this.padding = const EdgeInsets.all(16),
    this.spacing = 16,
    super.key,
  });

  /// The panels to lay out, in priority order.
  final List<Widget> panels;

  /// Outer padding of the grid.
  final EdgeInsets padding;

  /// Gap between panels and columns.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = switch (formFactorForWidth(constraints.maxWidth)) {
          FormFactor.compact => 1,
          FormFactor.medium => 2,
          FormFactor.expanded => 3,
        };

        if (columnCount == 1) {
          return ListView.separated(
            padding: padding,
            itemCount: panels.length,
            separatorBuilder: (_, _) => SizedBox(height: spacing),
            itemBuilder: (_, index) => panels[index],
          );
        }

        final columns = List.generate(columnCount, (_) => <Widget>[]);
        for (var index = 0; index < panels.length; index++) {
          columns[index % columnCount].add(panels[index]);
        }

        return SingleChildScrollView(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < columns.length; index++) ...[
                if (index > 0) SizedBox(width: spacing),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final panel in columns[index]) ...[
                        panel,
                        SizedBox(height: spacing),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A titled surface used for every dashboard section.
class PanelCard extends StatelessWidget {
  /// Creates a titled panel.
  const PanelCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    super.key,
  });

  /// Headline of the panel.
  final String title;

  /// Panel body.
  final Widget child;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trailing action.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A compact label/value row used inside panels.
class InfoRow extends StatelessWidget {
  /// Creates an info row.
  const InfoRow({required this.label, required this.value, this.icon, super.key});

  /// Left hand label.
  final String label;

  /// Right hand value.
  final String value;

  /// Optional leading icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
          ],
          Text(label, style: theme.textTheme.bodySmall),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown when a panel has nothing to display.
class EmptyHint extends StatelessWidget {
  /// Creates an empty state hint.
  const EmptyHint(this.message, {this.icon, super.key});

  /// Explanatory text.
  final String message;

  /// Optional illustration icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.info_outline,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

