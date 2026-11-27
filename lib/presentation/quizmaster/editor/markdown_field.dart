/// A text field for Markdown with a toolbar, shortcuts and a preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/quiz_markdown.dart';
import '../../l10n/app_localizations.dart';

class _Wrap extends Intent {
  const _Wrap(this.marker);
  final String marker;
}

/// The field of a prompt, a host note, a hint or a slide text.
class MarkdownField extends StatefulWidget {
  const MarkdownField({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.validator,
    this.label,
    this.minLines = 2,
    this.maxLines = 6,
    super.key,
  }) : assert(controller == null || initialValue == null);

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final String? label;
  final int minLines;
  final int maxLines;

  @override
  State<MarkdownField> createState() => _MarkdownFieldState();
}

class _MarkdownFieldState extends State<MarkdownField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue);
  final _focus = FocusNode();
  bool _preview = false;

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _apply(TextEditingValue value) {
    _controller.value = value;
    widget.onChanged?.call(value.text);
    _focus.requestFocus();
  }

  /// Puts [marker] around the selection (or removes it again).
  void _wrap(String marker, {String? after}) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final closing = after ?? marker;
    final text = value.text;
    final selected = selection.textInside(text);
    final before = selection.textBefore(text);
    final rest = selection.textAfter(text);
    if (before.endsWith(marker) && rest.startsWith(closing)) {
      _apply(
        TextEditingValue(
          text:
              before.substring(0, before.length - marker.length) +
              selected +
              rest.substring(closing.length),
          selection: TextSelection(
            baseOffset: selection.start - marker.length,
            extentOffset: selection.end - marker.length,
          ),
        ),
      );
      return;
    }
    _apply(
      TextEditingValue(
        text: '$before$marker$selected$closing$rest',
        selection: TextSelection(
          baseOffset: selection.start + marker.length,
          extentOffset: selection.end + marker.length,
        ),
      ),
    );
  }

  /// Starts every selected line with [prefix].
  void _prefix(String prefix) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = text.lastIndexOf('\n', selection.start - 1) + 1;
    var end = text.indexOf('\n', selection.end);
    if (end < 0) end = text.length;
    final lines = text.substring(start, end).split('\n');
    final changed = [
      for (final line in lines)
        line.startsWith(prefix)
            ? line.substring(prefix.length)
            : '$prefix$line',
    ].join('\n');
    _apply(
      TextEditingValue(
        text: text.replaceRange(start, end, changed),
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + changed.length,
        ),
      ),
    );
  }

  void _link() {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final label = selection.textInside(value.text);
    final inserted = '[${label.isEmpty ? 'Text' : label}](https://)';
    final cursor = selection.start + inserted.length - 1;
    _apply(
      TextEditingValue(
        text: value.text.replaceRange(selection.start, selection.end, inserted),
        selection: TextSelection.collapsed(offset: cursor),
      ),
    );
  }

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Formatierung')),
      content: SingleChildScrollView(
        child: SelectableText(
          [
            '**${context.tr('fett')}**   *${context.tr('kursiv')}*   ~~${context.tr('durchgestrichen')}~~',
            '# ${context.tr('Überschrift')}   ## …   ### …',
            '- ${context.tr('Punkt')}   1. ${context.tr('Punkt')}',
            '> ${context.tr('Zitat')}',
            '`Code`   ```${context.tr('Codeblock')}```',
            '---   [Text](https://…)   \\*',
            context.tr(
              'Ein Zeilenumbruch bleibt sichtbar. HTML, Bilder und Tabellen werden nicht umgewandelt.',
            ),
          ].join('\n\n'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Schließen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, String, VoidCallback)>[
      (Icons.format_bold, 'Fett (Strg+B)', () => _wrap('**')),
      (Icons.format_italic, 'Kursiv (Strg+I)', () => _wrap('*')),
      (Icons.format_list_bulleted, 'Liste', () => _prefix('- ')),
      (Icons.format_quote, 'Zitat', () => _prefix('> ')),
      (Icons.code, 'Code', () => _wrap('`')),
      (Icons.link, 'Link', _link),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (icon, tooltip, action) in tools)
              IconButton(
                tooltip: context.tr(tooltip),
                visualDensity: VisualDensity.compact,
                onPressed: _preview ? null : action,
                icon: Icon(icon),
              ),
            IconButton(
              tooltip: context.tr('Formatierung'),
              visualDensity: VisualDensity.compact,
              onPressed: _help,
              icon: const Icon(Icons.help_outline),
            ),
            TextButton.icon(
              key: const ValueKey('markdown-preview-toggle'),
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit : Icons.visibility_outlined),
              label: Text(context.tr(_preview ? 'Bearbeiten' : 'Vorschau')),
            ),
          ],
        ),
        // The field stays in the tree, so switching never loses input.
        Offstage(
          offstage: _preview,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyB, control: true): _Wrap(
                '**',
              ),
              SingleActivator(LogicalKeyboardKey.keyB, meta: true): _Wrap('**'),
              SingleActivator(LogicalKeyboardKey.keyI, control: true): _Wrap(
                '*',
              ),
              SingleActivator(LogicalKeyboardKey.keyI, meta: true): _Wrap('*'),
            },
            child: Actions(
              actions: {
                _Wrap: CallbackAction<_Wrap>(
                  onInvoke: (intent) => _wrap(intent.marker),
                ),
              },
              child: TextFormField(
                controller: _controller,
                focusNode: _focus,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                validator: widget.validator,
                onChanged: widget.onChanged,
                decoration: InputDecoration(labelText: widget.label),
              ),
            ),
          ),
        ),
        if (_preview)
          InputDecorator(
            decoration: InputDecoration(labelText: widget.label),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => QuizMarkdown(
                _controller.text,
                key: const ValueKey('markdown-preview'),
              ),
            ),
          ),
      ],
    );
  }
}
