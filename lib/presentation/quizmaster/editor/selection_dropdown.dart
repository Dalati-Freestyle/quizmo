import 'package:flutter/material.dart';

/// A labeled, scrollable selection field used throughout the quiz editor.
class SelectionDropdown<T> extends StatelessWidget {
  /// Creates a dropdown with [items] and the currently selected [value].
  const SelectionDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  /// The field label shown above the selection.
  final String label;

  /// The current selection, or `null` before an option is chosen.
  final T? value;

  /// The available selections.
  final List<DropdownMenuItem<T>> items;

  /// Receives the selected option.
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    isEmpty: value == null,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        menuMaxHeight: 320,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}
