/// Shows the Markdown of prompts, notes, hints and slides.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/markdown_text.dart';

/// A [Text] for Markdown: text without Markdown looks exactly as before, and
/// screen readers get the plain text.
///
/// Links only open on a click when [openLinks] is set (host notes); on
/// player and TV devices they are text. Nothing is ever loaded from outside.
class QuizMarkdown extends StatefulWidget {
  const QuizMarkdown(
    this.source, {
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.openLinks = false,
    this.selectable = false,
    super.key,
  });

  final String source;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool openLinks;
  final bool selectable;

  @override
  State<QuizMarkdown> createState() => _QuizMarkdownState();
}

class _QuizMarkdownState extends State<QuizMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  TextStyle _styleOf(MarkdownStyle style, TextStyle base, ThemeData theme) {
    var result = const TextStyle();
    if (style.bold) result = result.copyWith(fontWeight: FontWeight.w700);
    if (style.italic || style.quote) {
      result = result.copyWith(fontStyle: FontStyle.italic);
    }
    if (style.quote) {
      result = result.copyWith(color: theme.colorScheme.onSurfaceVariant);
    }
    if (style.strike) {
      result = result.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (style.code) {
      result = result.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      );
    }
    if (style.heading > 0) {
      final size = base.fontSize ?? 14;
      result = result.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: size * const [1.0, 1.5, 1.3, 1.15][style.heading],
      );
    }
    if (style.link != null) {
      result = result.copyWith(
        decoration: TextDecoration.underline,
        color: widget.openLinks && isOpenableLink(style.link)
            ? theme.colorScheme.primary
            : null,
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final theme = Theme.of(context);
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    final runs = markdownRuns(widget.source);
    final plain = runs.map((run) => run.text).join();
    final spans = [
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: _styleOf(run.style, base, theme),
          recognizer: widget.openLinks && isOpenableLink(run.style.link)
              ? (TapGestureRecognizer()
                  ..onTap = () => launchUrl(
                    Uri.parse(run.style.link!),
                    mode: LaunchMode.externalApplication,
                  ))
              : null,
        ),
    ];
    for (final span in spans) {
      if (span.recognizer case final TapGestureRecognizer recognizer) {
        _recognizers.add(recognizer);
      }
    }
    final text = TextSpan(children: spans);
    return widget.selectable
        ? SelectableText.rich(
            text,
            style: widget.style,
            maxLines: widget.maxLines,
            textAlign: widget.textAlign,
            semanticsLabel: plain,
          )
        : Text.rich(
            text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            textAlign: widget.textAlign,
            semanticsLabel: plain,
          );
  }
}
