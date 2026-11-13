/// Customisable layout of the host dashboard (admin view).
///
/// A pure host-device preference: it never reaches the game state, player or
/// TV snapshots or the quiz file.
library;

import 'dart:convert';

/// Sections of the host dashboard.
///
/// Format dependent content shares one section: [questions] shows the
/// Jeopardy board in a Jeopardy session and the question list otherwise, so
/// both inherit the settings of that slot.
enum DashboardSection {
  sessionAccess('Sitzungszugang', required: true),
  guestWifi('Gäste-WLAN', required: false),
  recovery('Spielstand-Sicherung', required: true),
  startQuiz('Quiz starten', required: true),
  liveRound('Laufende Runde', required: true),
  media('Medienwiedergabe', required: true),
  poker('Pokerchips', required: true),
  questions('Fragen / Board', required: true),
  server('Server', required: true),
  scoreboard('Rangliste', required: false),
  corrections('Korrekturverlauf', required: false),
  report('Ergebnisbericht', required: false),
  players('Spieler', required: true),
  serverLog('Server-Log', required: false);

  const DashboardSection(this.titleKey, {required this.required});

  /// Message key of the section title.
  final String titleKey;

  /// Whether the game cannot run without the section; it cannot be hidden,
  /// only minimised.
  final bool required;
}

/// Number of colours offered for the sections.
const kDashboardPaletteSize = 16;

/// Per section settings.
final class DashboardSectionSettings {
  /// Creates settings for [section].
  const DashboardSectionSettings({
    required this.section,
    required this.colorIndex,
    this.visible = true,
    this.expanded = true,
  });

  /// The section.
  final DashboardSection section;

  /// Index into the colour palette.
  final int colorIndex;

  /// Whether the section is shown; required sections are always shown.
  final bool visible;

  /// Whether the section is expanded; toggling it on the dashboard is
  /// remembered.
  final bool expanded;

  /// Effective visibility.
  bool get isVisible => visible || section.required;

  /// Returns a copy with the given fields replaced.
  DashboardSectionSettings copyWith({
    int? colorIndex,
    bool? visible,
    bool? expanded,
  }) => DashboardSectionSettings(
    section: section,
    colorIndex: colorIndex ?? this.colorIndex,
    visible: visible ?? this.visible,
    expanded: expanded ?? this.expanded,
  );

  Map<String, Object?> _toJson() => {
    'id': section.name,
    'color': colorIndex,
    'visible': visible,
    'expanded': expanded,
  };

  @override
  bool operator ==(Object other) =>
      other is DashboardSectionSettings &&
      other.section == section &&
      other.colorIndex == colorIndex &&
      other.visible == visible &&
      other.expanded == expanded;

  @override
  int get hashCode => Object.hash(section, colorIndex, visible, expanded);
}

/// Order, colour, visibility and default expansion of all sections.
final class DashboardLayout {
  /// Creates a layout from [sections] (completed with defaults).
  DashboardLayout(List<DashboardSectionSettings> sections)
    : sections = List.unmodifiable(_complete(sections));

  /// The default layout: every section in its own colour, server log hidden.
  factory DashboardLayout.standard() => DashboardLayout([
    for (final section in DashboardSection.values) _default(section),
  ]);

  /// Restores a stored layout.
  ///
  /// Never throws: unknown sections are skipped, invalid values fall back to
  /// defaults, and sections added in a later version appear with their
  /// default settings at their default position.
  factory DashboardLayout.decode(String? source) {
    if (source == null || source.isEmpty) return DashboardLayout.standard();
    try {
      final json = jsonDecode(source);
      if (json is! Map || json['sections'] is! List) {
        return DashboardLayout.standard();
      }
      final sections = <DashboardSectionSettings>[];
      for (final entry in json['sections'] as List) {
        if (entry is! Map) continue;
        final section = DashboardSection.values
            .where((value) => value.name == entry['id'])
            .firstOrNull;
        if (section == null || sections.any((s) => s.section == section)) {
          continue;
        }
        final fallback = _default(section);
        final color = entry['color'];
        sections.add(
          DashboardSectionSettings(
            section: section,
            colorIndex:
                color is int && color >= 0 && color < kDashboardPaletteSize
                ? color
                : fallback.colorIndex,
            visible: entry['visible'] is bool
                ? entry['visible'] as bool
                : fallback.visible,
            expanded: entry['expanded'] is bool
                ? entry['expanded'] as bool
                : fallback.expanded,
          ),
        );
      }
      return DashboardLayout(sections);
    } on Object {
      return DashboardLayout.standard();
    }
  }

  /// Sections in display order.
  final List<DashboardSectionSettings> sections;

  /// Settings of [section].
  DashboardSectionSettings operator [](DashboardSection section) =>
      sections.firstWhere((entry) => entry.section == section);

  /// Marker of exported layout files.
  static const fileType = 'quizmo-dashboard-layout';

  /// Suggested name of an exported layout file.
  static const fileName = 'quizmo-admin-ansicht.json';

  /// Reads an exported layout file.
  ///
  /// Unlike [DashboardLayout.decode] it rejects files that are not a Quizmo
  /// layout with a [FormatException], so an import never silently resets the
  /// view. Unknown sections and invalid values still fall back to defaults.
  factory DashboardLayout.parseFile(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Die Datei ist kein gültiges JSON.');
    }
    if (json is! Map || json['type'] != fileType || json['sections'] is! List) {
      throw const FormatException(
        'Die Datei ist keine Quizmo-Layoutdatei für die Admin-Ansicht.',
      );
    }
    return DashboardLayout.decode(source);
  }

  /// Serializes the layout (also the export file format).
  String encode() => jsonEncode({
    'type': fileType,
    'version': 1,
    'sections': [for (final entry in sections) entry._toJson()],
  });

  /// Moves the section at [oldIndex] so that it ends up at [newIndex].
  DashboardLayout move(int oldIndex, int newIndex) {
    final list = [...sections];
    final entry = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), entry);
    return DashboardLayout(list);
  }

  /// Replaces the settings of one section.
  DashboardLayout update(DashboardSectionSettings settings) => DashboardLayout([
    for (final entry in sections)
      entry.section == settings.section ? settings : entry,
  ]);

  /// Gives every section the colour [colorIndex].
  DashboardLayout withColor(int colorIndex) => DashboardLayout([
    for (final entry in sections) entry.copyWith(colorIndex: colorIndex),
  ]);

  @override
  bool operator ==(Object other) =>
      other is DashboardLayout &&
      other.sections.length == sections.length &&
      [
        for (var i = 0; i < sections.length; i++)
          other.sections[i] == sections[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hashAll(sections);

  static DashboardSectionSettings _default(DashboardSection section) =>
      DashboardSectionSettings(
        section: section,
        colorIndex: section.index % kDashboardPaletteSize,
        visible: section != DashboardSection.serverLog,
        expanded: section != DashboardSection.serverLog,
      );

  static List<DashboardSectionSettings> _complete(
    List<DashboardSectionSettings> stored,
  ) {
    final result = [...stored];
    for (final section in DashboardSection.values) {
      if (result.any((entry) => entry.section == section)) continue;
      // Insert a new section after its default predecessor that is present.
      final predecessors = DashboardSection.values.take(section.index);
      var index = 0;
      for (final previous in predecessors.toList().reversed) {
        final position = result.indexWhere((e) => e.section == previous);
        if (position >= 0) {
          index = position + 1;
          break;
        }
      }
      result.insert(index, _default(section));
    }
    return result;
  }
}
