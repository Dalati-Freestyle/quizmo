/// Swatches of the shared named palette ([TeamColor]).
library;

import 'package:flutter/material.dart';

import '../../core/models/team_color.dart';
import '../l10n/app_localizations.dart';

/// Lets the user pick one palette colour by tapping its swatch.
///
/// Every swatch carries the colour's name as tooltip and semantics label, so
/// the colour is never the only cue.
class PaletteColorPicker extends StatelessWidget {
  /// Creates the picker.
  const PaletteColorPicker({
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'palette',
    super.key,
  });

  /// The current colour, marked with a check.
  final TeamColor? selected;

  /// Receives the tapped colour.
  final ValueChanged<TeamColor> onSelected;

  /// Prefix of the swatch keys (`<prefix>-<index>`).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final color in TeamColor.values)
        Tooltip(
          message: context.tr(color.labelKey),
          child: Semantics(
            button: true,
            selected: color == selected,
            label: context.tr(color.labelKey),
            child: InkWell(
              key: ValueKey('$keyPrefix-${color.index}'),
              customBorder: const CircleBorder(),
              onTap: () => onSelected(color),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Color(color.argb),
                child: color == selected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ),
    ],
  );
}
