/// Settings screen "Admin-Ansicht anpassen".
library;

import 'dart:async';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../../core/models/team_color.dart';
import '../../common/palette_color_picker.dart';
import 'dashboard_layout.dart';
import 'dashboard_layout_store.dart';
import 'dashboard_section_view.dart';

/// Edits order (drag and drop), colour, visibility and default expansion of
/// every admin view section.
class DashboardLayoutSettingsPage extends StatefulWidget {
  /// Creates the page.
  const DashboardLayoutSettingsPage({
    this.pickLayoutFile = _pickLayoutFile,
    this.saveLayoutFile = _saveLayoutFile,
    super.key,
  });

  /// Lets the host pick a layout file; returns its text or `null`.
  final Future<String?> Function() pickLayoutFile;

  /// Offers [contents] as a download or save dialog; `false` if cancelled.
  final Future<bool> Function(String contents) saveLayoutFile;

  static Future<String?> _pickLayoutFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  static Future<bool> _saveLayoutFile(String contents) async =>
      await FilePicker.saveFile(
        fileName: DashboardLayout.fileName,
        bytes: utf8.encode(contents),
      ) !=
      null;

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

  Future<void> _export(DashboardLayout layout) => _exportFile(layout.encode());

  Future<void> _exportFile(String contents) async {
    try {
      await widget.saveLayoutFile(contents);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Das Layout konnte nicht exportiert werden.');
      }
    }
  }

  Future<void> _import() async {
    final String? contents;
    try {
      contents = await widget.pickLayoutFile();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Die Datei konnte nicht gelesen werden.');
      }
      return;
    }
    if (contents == null) return;
    final DashboardLayout layout;
    try {
      layout = DashboardLayout.parseFile(contents);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return;
    }
    await _save(layout);
    // Imported layouts also land in the library to switch back later.
    final name =
        NamedDashboardLayout.nameInFile(contents) ??
        (mounted ? context.tr('Importiertes Layout') : 'Importiertes Layout');
    await _storeInLibrary(name, layout);
    if (mounted && _error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('Layout importiert.'))));
    }
  }

  Future<void> _storeInLibrary(String name, DashboardLayout layout) async {
    try {
      await _store.saveAs(name, layout);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = 'Die Layout-Bibliothek konnte nicht gespeichert werden.',
        );
      }
    }
  }

  Future<String?> _askName({String initial = ''}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _LayoutNameDialog(initial: initial),
    );
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _saveAs(DashboardLayout layout) async {
    final name = await _askName();
    if (name != null) await _storeInLibrary(name, layout);
  }

  Future<void> _openLibrary() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.tr('Gespeicherte Layouts')),
      content: SizedBox(
        width: 420,
        child: ValueListenableBuilder<List<NamedDashboardLayout>>(
          valueListenable: _store.library,
          builder: (context, entries, _) => entries.isEmpty
              ? Text(
                  context.tr(
                    'Noch keine Layouts gespeichert. „Speichern“ legt das aktuelle Layout hier ab.',
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in entries)
                      ListTile(
                        key: ValueKey('layout-library-${entry.name}'),
                        leading: Icon(
                          entry.layout == _store.layout.value
                              ? Icons.check_circle
                              : Icons.dashboard_outlined,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(context.tr('Antippen zum Anwenden')),
                        onTap: () async {
                          await _save(entry.layout);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        trailing: PopupMenuButton<String>(
                          key: ValueKey('layout-library-menu-${entry.name}'),
                          onSelected: (action) async {
                            switch (action) {
                              case 'rename':
                                final name = await _askName(
                                  initial: entry.name,
                                );
                                if (name != null) {
                                  await _store.rename(entry.name, name);
                                }
                              case 'export':
                                await _exportFile(entry.encodeFile());
                              case 'delete':
                                await _store.delete(entry.name);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(context.tr('Umbenennen')),
                            ),
                            PopupMenuItem(
                              value: 'export',
                              child: Text(context.tr('Exportieren')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(context.tr('Löschen')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.tr('Schließen')),
        ),
      ],
    ),
  );

  Future<int?> _pickColor(int? current) => showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Farbe wählen')),
      content: PaletteColorPicker(
        selected: current == null ? null : TeamColor.values[current],
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
                'Am einfachsten passt du die Ansicht direkt in der Admin-Ansicht an („Ansicht anpassen“). Hier siehst du dasselbe Raster mit allen Bereichen. Pflichtbereiche lassen sich nicht ausblenden, aber minimieren. Die Anpassung gilt auf diesem Gerät; per Export und Import lässt sie sich übertragen.',
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
                OutlinedButton.icon(
                  key: const ValueKey('layout-save-as'),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(context.tr('Speichern')),
                  onPressed: () => _saveAs(layout),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('layout-library'),
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  label: Text(context.tr('Gespeicherte Layouts')),
                  onPressed: _openLibrary,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('layout-export'),
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(context.tr('Layout exportieren')),
                  onPressed: () => _export(layout),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('layout-import'),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(context.tr('Layout importieren')),
                  onPressed: _import,
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
          // The same grid as the admin view, with every section as a
          // placeholder tile: drag, colour and hide them in place.
          const Expanded(
            child: DashboardSectionGrid(
              sections: {},
              editable: false,
              alwaysEditing: true,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the name of a saved layout; owns its text controller.
class _LayoutNameDialog extends StatefulWidget {
  const _LayoutNameDialog({required this.initial});

  final String initial;

  @override
  State<_LayoutNameDialog> createState() => _LayoutNameDialogState();
}

class _LayoutNameDialogState extends State<_LayoutNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Name des Layouts')),
    content: TextField(
      key: const ValueKey('layout-name'),
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('Abbrechen')),
      ),
      FilledButton(
        key: const ValueKey('layout-name-ok'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.tr('Speichern')),
      ),
    ],
  );
}
