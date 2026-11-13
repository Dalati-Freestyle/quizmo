/// Settings screen "Admin-Ansicht anpassen".
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_store.dart';
import 'dashboard_section_view.dart';

/// Edits order (drag and drop), colour, visibility and default expansion of
/// every admin view section.
class DashboardLayoutSettingsPage extends StatefulWidget {
  /// Creates the page.
  const DashboardLayoutSettingsPage({super.key});

  @override
  State<DashboardLayoutSettingsPage> createState() =>
      _DashboardLayoutSettingsPageState();
}

class _DashboardLayoutSettingsPageState
    extends State<DashboardLayoutSettingsPage> {
  final _store = DashboardLayoutStore.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  Future<void> _save(DashboardLayout layout) async {
    try {
      await _store.save(layout);
      if (mounted && _error != null) setState(() => _error = null);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Die Anpassung gilt jetzt, konnte aber nicht dauerhaft gespeichert werden.',
        );
      }
    }
  }

  Future<int?> _pickColor(int? current) => showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Farbe wählen')),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var index = 0; index < kDashboardPalette.length; index++)
            Semantics(
              button: true,
              selected: index == current,
              label: context.tr('Farbe {0}', [index + 1]),
              child: InkWell(
                key: ValueKey('palette-$index'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context, index),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: kDashboardPalette[index],
                  child: index == current
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Abbrechen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Admin-Ansicht anpassen'))),
    body: ValueListenableBuilder<DashboardLayout>(
      valueListenable: _store.layout,
      builder: (context, layout, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              context.tr(
                'Reihenfolge per Ziehen am Griff ändern. Pflichtbereiche lassen sich nicht ausblenden. Die Anpassung gilt nur auf diesem Gerät.',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('layout-same-color'),
                  icon: const Icon(Icons.format_color_fill),
                  label: Text(context.tr('Allen Bereichen dieselbe Farbe')),
                  onPressed: () async {
                    final color = await _pickColor(null);
                    if (color != null) await _save(layout.withColor(color));
                  },
                ),
                OutlinedButton.icon(
                  key: const ValueKey('layout-reset'),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(context.tr('Standardlayout wiederherstellen')),
                  onPressed: () => _save(DashboardLayout.standard()),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              buildDefaultDragHandles: false,
              itemCount: layout.sections.length,
              onReorderItem: (from, to) => _save(layout.move(from, to)),
              itemBuilder: (context, index) {
                final entry = layout.sections[index];
                final color = kDashboardPalette[entry.colorIndex];
                final title = context.tr(entry.section.titleKey);
                return Card(
                  key: ValueKey(entry.section),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.drag_indicator,
                              semanticLabel: context.tr('{0} verschieben', [
                                title,
                              ]),
                            ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey('layout-color-${entry.section.name}'),
                          tooltip: context.tr('Farbe von {0}', [title]),
                          icon: CircleAvatar(
                            radius: 12,
                            backgroundColor: color,
                          ),
                          onPressed: () async {
                            final picked = await _pickColor(entry.colorIndex);
                            if (picked != null) {
                              await _save(
                                layout.update(
                                  entry.copyWith(colorIndex: picked),
                                ),
                              );
                            }
                          },
                        ),
                        Icon(dashboardSectionIcon(entry.section), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.section.required
                                ? '$title (${context.tr('Pflicht')})'
                                : title,
                          ),
                        ),
                        Tooltip(
                          message: context.tr('Anzeigen'),
                          child: Switch(
                            key: ValueKey(
                              'layout-visible-${entry.section.name}',
                            ),
                            value: entry.isVisible,
                            onChanged: entry.section.required
                                ? null
                                : (value) => _save(
                                    layout.update(
                                      entry.copyWith(visible: value),
                                    ),
                                  ),
                          ),
                        ),
                        IconButton(
                          key: ValueKey(
                            'layout-expanded-${entry.section.name}',
                          ),
                          tooltip: context.tr(
                            entry.expanded
                                ? 'Startet ausgeklappt'
                                : 'Startet minimiert',
                          ),
                          icon: Icon(
                            entry.expanded
                                ? Icons.unfold_more
                                : Icons.unfold_less,
                          ),
                          onPressed: () => _save(
                            layout.update(
                              entry.copyWith(expanded: !entry.expanded),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
