/// Editor for the hints of one question.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import '../../l10n/app_localizations.dart';
import 'media_editor.dart';

/// Lists the hints in the order the host shows them.
class HintsEditor extends StatefulWidget {
  /// Creates the editor; [costsPoints] is `false` in formats without points.
  const HintsEditor({
    required this.hints,
    required this.onChanged,
    this.costsPoints = true,
    super.key,
  });

  final List<QuestionHint> hints;
  final ValueChanged<List<QuestionHint>> onChanged;
  final bool costsPoints;

  @override
  State<HintsEditor> createState() => _HintsEditorState();
}

class _HintsEditorState extends State<HintsEditor> {
  late List<QuestionHint> _hints = [...widget.hints];

  void _update(List<QuestionHint> hints) {
    setState(() => _hints = hints);
    widget.onChanged([...hints]);
  }

  Future<void> _edit([int? index]) async {
    final edited = await showDialog<QuestionHint>(
      context: context,
      builder: (_) => HintEditorDialog(
        hint: index == null ? const QuestionHint() : _hints[index],
        costsPoints: widget.costsPoints,
      ),
    );
    if (edited == null || !mounted) return;
    _update([
      for (final (i, hint) in _hints.indexed) i == index ? edited : hint,
      if (index == null) edited,
    ]);
  }

  void _move(int index, int offset) {
    final hints = [..._hints];
    final hint = hints.removeAt(index);
    hints.insert(index + offset, hint);
    _update(hints);
  }

  String _subtitle(BuildContext context, QuestionHint hint) => [
    if (widget.costsPoints)
      hint.cost > 0
          ? context.tr('−{0} Punkte', [hint.cost])
          : context.tr('kostenlos'),
    if (hint.media.isNotEmpty) context.tr('{0} Medien', [hint.media.length]),
  ].join(' · ');

  @override
  Widget build(BuildContext context) => PanelCard(
    title: context.tr('Tipps (optional)'),
    icon: Icons.lightbulb_outline,
    trailing: IconButton(
      key: const ValueKey('add-hint'),
      tooltip: context.tr('Tipp hinzufügen'),
      onPressed: _hints.length >= QuestionHint.maxPerQuestion
          ? null
          : () => _edit(),
      icon: const Icon(Icons.add),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hints.isEmpty)
          EmptyHint(
            context.tr(
              'Keine Tipps. Der Spielleiter deckt sie während der Frage nacheinander auf.',
            ),
          ),
        if (!widget.costsPoints)
          Text(context.tr('Im Pokerchips-Format sind Tipps immer kostenlos.')),
        for (final (index, hint) in _hints.indexed)
          ListTile(
            key: ValueKey('hint-$index'),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 14, child: Text('${index + 1}')),
            title: Text(
              hint.text.trim().isEmpty
                  ? context.tr('Tipp {0}', [index + 1])
                  : hint.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_subtitle(context, hint)),
            onTap: () => _edit(index),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.tr('Nach oben'),
                  onPressed: index == 0 ? null : () => _move(index, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: context.tr('Nach unten'),
                  onPressed: index == _hints.length - 1
                      ? null
                      : () => _move(index, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: context.tr('Tipp entfernen'),
                  onPressed: () => _update([..._hints]..removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Edits text, point deduction and media of one hint.
class HintEditorDialog extends StatefulWidget {
  /// Creates the dialog for [hint].
  const HintEditorDialog({
    required this.hint,
    this.costsPoints = true,
    super.key,
  });

  final QuestionHint hint;
  final bool costsPoints;

  @override
  State<HintEditorDialog> createState() => _HintEditorDialogState();
}

class _HintEditorDialogState extends State<HintEditorDialog> {
  late String _text = widget.hint.text;
  late String _cost = '${widget.hint.cost}';
  late List<MediaAttachment> _media = widget.hint.media;

  @override
  Widget build(BuildContext context) {
    // Anything but a whole number is as invalid as a negative deduction.
    final hint = QuestionHint(
      text: _text.trim(),
      media: _media,
      cost: int.tryParse(_cost.trim().isEmpty ? '0' : _cost.trim()) ?? -1,
    );
    final errors = hint.validationErrors;
    return AlertDialog(
      title: Text(context.tr('Tipp')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Room for the floating label of the first field.
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('hint-text'),
                initialValue: _text,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(labelText: context.tr('Text')),
                onChanged: (value) => setState(() => _text = value),
              ),
              const SizedBox(height: 12),
              if (widget.costsPoints) ...[
                TextFormField(
                  key: const ValueKey('hint-cost'),
                  initialValue: _cost,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Punktabzug (0 = kostenlos)'),
                    helperText: context.tr(
                      'Wer erst nach diesem Tipp richtig antwortet, erhält so viele Punkte weniger (mindestens 0). Falsche Antworten bleiben unverändert.',
                    ),
                    helperMaxLines: 4,
                  ),
                  onChanged: (value) => setState(() => _cost = value),
                ),
                const SizedBox(height: 12),
              ],
              MediaEditor(
                title: context.tr('Medien des Tipps'),
                media: _media,
                onChanged: (media) => setState(() => _media = media),
              ),
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('save-hint'),
          onPressed: errors.isEmpty
              ? () => Navigator.of(context).pop(hint)
              : null,
          child: Text(context.tr('Save')),
        ),
      ],
    );
  }
}
