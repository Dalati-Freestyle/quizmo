/// Category input of the editor: pick a category of the quiz or type a new
/// one.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A text field for a category with a menu of the [categories] that already
/// exist in the quiz. Choosing one fills the field, typing creates a new one;
/// questions and slides with the same category belong together.
class CategoryField extends StatelessWidget {
  /// Creates the field around [controller].
  const CategoryField({
    required this.controller,
    required this.categories,
    required this.label,
    this.helperText,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;

  /// Existing categories of the quiz, each once.
  final List<String> categories;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 4,
      suffixIcon: categories.isEmpty
          ? null
          : PopupMenuButton<String>(
              key: const ValueKey('category-menu'),
              tooltip: context.tr('Bestehende Kategorie wählen'),
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (category) {
                controller.text = category;
                onChanged?.call(category);
              },
              itemBuilder: (context) => [
                for (final category in categories)
                  PopupMenuItem(value: category, child: Text(category)),
              ],
            ),
    ),
  );
}
