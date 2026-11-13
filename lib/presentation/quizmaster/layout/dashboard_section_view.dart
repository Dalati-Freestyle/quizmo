/// Collapsible, colour coded frame around a host dashboard section.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../common/adaptive_layout.dart';
import '../../common/palette_color_picker.dart';
import '../../../core/models/team_color.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_store.dart';

/// Section colours; the same named palette as the team colours
/// ([TeamColor]). Distinguishable hues that work in light and dark themes as
/// accent strips and tinted headers (text stays in the theme colours).
final kDashboardPalette = List<Color>.unmodifiable([
  for (final color in TeamColor.values) Color(color.argb),
]);

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
    this.onExpandedChanged,
    super.key,
  });

  /// Receives a toggle, so that the layout remembers it.
  final ValueChanged<bool>? onExpandedChanged;

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
              onTap: () {
                setState(() => _expanded = !_expanded);
                widget.onExpandedChanged?.call(_expanded);
              },
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
              child: InSectionFrame(child: widget.child),
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
///
/// The layout is edited right here, in the real grid ("Ansicht anpassen"):
/// tiles keep their positions, are dragged by their handle onto another
/// tile, and colour and visibility are changed on the tile itself. Sections
/// that the current game does not show appear as placeholders while editing,
/// so they can be placed too.
class DashboardSectionGrid extends StatefulWidget {
  /// Creates the grid.
  const DashboardSectionGrid({
    required this.sections,
    this.leading = const [],
    this.editable = true,
    this.alwaysEditing = false,
    super.key,
  });

  /// Panels per section that exist in the current game state.
  final Map<DashboardSection, Widget> sections;

  /// Full-width widgets above the grid (e.g. warnings).
  final List<Widget> leading;

  /// Whether the "customise view" toggle is offered.
  final bool editable;

  /// Whether the grid always shows the editing tiles (settings screen).
  final bool alwaysEditing;

  @override
  State<DashboardSectionGrid> createState() => _DashboardSectionGridState();
}

class _DashboardSectionGridState extends State<DashboardSectionGrid> {
  final _store = DashboardLayoutStore.instance;
  bool _editing = false;

  bool get _isEditing => widget.alwaysEditing || _editing;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  Future<void> _save(DashboardLayout layout) async {
    try {
      await _store.save(layout);
    } on Object {
      // The change applies for this session; the settings screen reports
      // storage problems.
    }
  }

  Future<void> _pickColor(DashboardSectionSettings entry) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Farbe wählen')),
        content: PaletteColorPicker(
          selected: TeamColor.values[entry.colorIndex],
          onSelected: (color) => Navigator.pop(context, color.index),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Abbrechen')),
          ),
        ],
      ),
    );
    if (picked != null) {
      await _save(
        _store.layout.value.update(entry.copyWith(colorIndex: picked)),
      );
    }
  }

  void _move(DashboardSection source, DashboardSection target) {
    final layout = _store.layout.value;
    final from = layout.sections.indexWhere((e) => e.section == source);
    final to = layout.sections.indexWhere((e) => e.section == target);
    if (from < 0 || to < 0 || from == to) return;
    unawaited(_save(layout.move(from, to)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DashboardLayout>(
    valueListenable: _store.layout,
    builder: (context, layout, _) {
      final grid = AdaptivePanelGrid(
        panels: _isEditing
            ? [
                for (final entry in layout.sections)
                  _EditableTile(
                    key: ValueKey('edit-${entry.section.name}'),
                    settings: entry,
                    present: widget.sections.containsKey(entry.section),
                    onMove: (source) => _move(source, entry.section),
                    onColor: () => _pickColor(entry),
                    onToggleVisible: entry.section.required
                        ? null
                        : () => unawaited(
                            _save(
                              layout.update(
                                entry.copyWith(visible: !entry.visible),
                              ),
                            ),
                          ),
                  ),
              ]
            : [
                for (final entry in layout.sections)
                  if (entry.isVisible)
                    if (widget.sections[entry.section] case final panel?)
                      DashboardSectionView(
                        key: ValueKey(entry.section),
                        settings: entry,
                        onExpandedChanged: (expanded) => _store.remember(
                          _store.layout.value.update(
                            _store.layout.value[entry.section].copyWith(
                              expanded: expanded,
                            ),
                          ),
                        ),
                        child: panel,
                      ),
              ],
      );
      final toolbar = widget.editable && !widget.alwaysEditing;
      if (!toolbar && widget.leading.isEmpty && !_isEditing) return grid;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in widget.leading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: item,
            ),
          if (toolbar || _isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_isEditing)
                    Text(
                      context.tr(
                        'Kacheln am Griff auf eine andere Kachel ziehen, um sie umzuordnen. Farbe und Sichtbarkeit direkt an der Kachel ändern.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (toolbar)
                    _editing
                        ? FilledButton.icon(
                            key: const ValueKey('dashboard-edit-done'),
                            icon: const Icon(Icons.check),
                            label: Text(context.tr('Fertig')),
                            onPressed: () => setState(() => _editing = false),
                          )
                        : TextButton.icon(
                            key: const ValueKey('dashboard-edit'),
                            icon: const Icon(
                              Icons.dashboard_customize_outlined,
                            ),
                            label: Text(context.tr('Ansicht anpassen')),
                            onPressed: () => setState(() => _editing = true),
                          ),
                ],
              ),
            ),
          Expanded(child: grid),
        ],
      );
    },
  );
}

/// A section while the view is being customised: a drag handle, colour and
/// visibility at the tile's real position in the grid.
class _EditableTile extends StatelessWidget {
  const _EditableTile({
    required this.settings,
    required this.present,
    required this.onMove,
    required this.onColor,
    required this.onToggleVisible,
    super.key,
  });

  final DashboardSectionSettings settings;
  final bool present;
  final ValueChanged<DashboardSection> onMove;
  final VoidCallback onColor;
  final VoidCallback? onToggleVisible;

  Widget _tile(BuildContext context, {bool highlighted = false}) {
    final theme = Theme.of(context);
    final color = kDashboardPalette[settings.colorIndex];
    final section = settings.section;
    final title = context.tr(section.titleKey);
    return Opacity(
      opacity: settings.isVisible ? 1 : 0.45,
      child: Material(
        color: Color.alphaBlend(
          color.withValues(alpha: highlighted ? 0.35 : 0.18),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: color, width: 6)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Draggable<DashboardSection>(
                key: ValueKey('edit-handle-${section.name}'),
                data: section,
                feedback: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(title, style: theme.textTheme.labelLarge),
                  ),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator,
                      semanticLabel: context.tr('{0} verschieben', [title]),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('edit-color-${section.name}'),
                tooltip: context.tr('Farbe von {0}', [title]),
                icon: CircleAvatar(radius: 10, backgroundColor: color),
                onPressed: onColor,
              ),
              Icon(dashboardSectionIcon(section), size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.required
                          ? '$title (${context.tr('Pflicht')})'
                          : title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!present)
                      Text(
                        context.tr('Gerade nicht sichtbar'),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('edit-visible-${section.name}'),
                tooltip: context.tr(
                  section.required
                      ? 'Pflichtbereich, nur minimierbar'
                      : settings.isVisible
                      ? 'Ausblenden'
                      : 'Anzeigen',
                ),
                icon: Icon(
                  settings.isVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: onToggleVisible,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DragTarget<DashboardSection>(
    onWillAcceptWithDetails: (details) => details.data != settings.section,
    onAcceptWithDetails: (details) => onMove(details.data),
    builder: (context, candidates, _) =>
        _tile(context, highlighted: candidates.isNotEmpty),
  );
}
