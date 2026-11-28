/// Warning when only some questions have a slide for their category.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Some questions have a slide for their category, others do not: with
/// "category slide before every question" only some get one.
class CategorySlidesWarning extends StatelessWidget {
  const CategorySlidesWarning({
    required this.missing,
    required this.total,
    this.categories = const [],
    super.key,
  });

  /// Questions without a slide for their category.
  final int missing;

  /// All questions.
  final int total;

  /// Categories without a slide, when known.
  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('category-slides-warning'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              [
                context.tr(
                  '{0} von {1} Fragen haben keine Folie zu ihrer Kategorie. Sie starten ohne Kategorie-Folie.',
                  [missing, total],
                ),
                if (categories.isNotEmpty)
                  context.tr('Ohne Folie: {0}', [categories.join(', ')]),
              ].join(' '),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
