/// Collapsible, colour coded frame around a host dashboard section.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../common/adaptive_layout.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_store.dart';

/// Section colours; distinguishable hues that work in light and dark themes
/// as accent strips and tinted headers (text stays in the theme colours).
const kDashboardPalette = <Color>[
  Color(0xFF3F6FD8), // blue
  Color(0xFF1E9E8F), // teal
  Color(0xFFD9822B), // orange
  Color(0xFF8E5BD6), // purple
  Color(0xFF2E9E4F), // green
  Color(0xFFD64F7A), // pink
  Color(0xFFB59A12), // ochre
  Color(0xFF0B8FC4), // cyan
  Color(0xFFC0392B), // red
  Color(0xFF6D7F1A), // olive
  Color(0xFF5C6BC0), // indigo
  Color(0xFF8D6E63), // brown
  Color(0xFF00897B), // dark teal
  Color(0xFFAD5FB0), // orchid
  Color(0xFF607D8B), // slate
  Color(0xFFE0682B), // vermilion
];

/// Icon of [section].
IconData dashboardSectionIcon(DashboardSection section) => switch (section) {
  DashboardSection.sessionAccess => Icons.lock_outline,
  DashboardSection.guestWifi => Icons.wifi,
  DashboardSection.recovery => Icons.save_outlined,
  DashboardSection.startQuiz => Icons.play_circle_outline,
  DashboardSection.liveRound => Icons.sports_esports_outlined,
  DashboardSection.media => Icons.live_tv,
  DashboardSection.poker => Icons.casino_outlined,
  DashboardSection.questions => Icons.grid_view,
  DashboardSection.server => Icons.dns_outlined,
  DashboardSection.scoreboard => Icons.leaderboard_outlined,
  DashboardSection.corrections => Icons.history,
  DashboardSection.report => Icons.summarize_outlined,
  DashboardSection.players => Icons.groups_outlined,
  DashboardSection.serverLog => Icons.receipt_long_outlined,
};

/// Wraps [child] with a coloured header that collapses and expands it.
///
/// Colour is never the only cue: every header keeps its title and icon.
class DashboardSectionView extends StatefulWidget {
  /// Creates the frame.
  const DashboardSectionView({
    required this.settings,
    required this.child,
    super.key,
  });

  /// Settings of the section (colour and initial expansion).
  final DashboardSectionSettings settings;

  /// The panel.
  final Widget child;

  @override
  State<DashboardSectionView> createState() => _DashboardSectionViewState();
}

class _DashboardSectionViewState extends State<DashboardSectionView> {
  late bool _expanded = widget.settings.expanded;

  @override
  void didUpdateWidget(DashboardSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.expanded != widget.settings.expanded) {
      _expanded = widget.settings.expanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = kDashboardPalette[widget.settings.colorIndex];
    final section = widget.settings.section;
    final title = context.tr(section.titleKey);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.18),
              theme.colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: ValueKey('dashboard-section-${section.name}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(dashboardSectionIcon(section), size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      semanticLabel: context.tr(
                        _expanded ? '{0} minimieren' : '{0} aufklappen',
                        [title],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Lays out the dashboard [sections] in the order, colours and visibility of
/// the stored [DashboardLayout].
///
/// Sections that are absent from [sections] (e.g. the poker panel in a
/// standard quiz) are skipped; hidden sections are never built.
class DashboardSectionGrid extends StatefulWidget {
  /// Creates the grid.
  const DashboardSectionGrid({required this.sections, super.key});

  /// Panels per section that exist in the current game state.
  final Map<DashboardSection, Widget> sections;

  @override
  State<DashboardSectionGrid> createState() => _DashboardSectionGridState();
}

class _DashboardSectionGridState extends State<DashboardSectionGrid> {
  final _store = DashboardLayoutStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DashboardLayout>(
    valueListenable: _store.layout,
    builder: (context, layout, _) => AdaptivePanelGrid(
      panels: [
        for (final entry in layout.sections)
          if (entry.isVisible)
            if (widget.sections[entry.section] case final panel?)
              DashboardSectionView(
                key: ValueKey(entry.section),
                settings: entry,
                child: panel,
              ),
      ],
    ),
  );
}
