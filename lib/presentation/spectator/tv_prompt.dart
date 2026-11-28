/// The question text on the TV: always complete, never cut off.
library;

import 'package:flutter/material.dart';

import '../../core/models/markdown_text.dart';
import '../common/quiz_markdown.dart';

/// Shows [prompt] in the space of [lines] lines of [style]. A longer text
/// (e.g. a list of items) gets a smaller type size instead of being cut off;
/// the canvas cannot scroll.
class TvPrompt extends StatelessWidget {
  const TvPrompt({
    required this.prompt,
    required this.lines,
    required this.style,
    super.key,
  });

  final String prompt;
  final int lines;
  final TextStyle? style;

  /// The smallest type size the TV uses for text.
  static const double minFontSize = 22;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final maxSize = base.fontSize ?? 48;
    final lineHeight = base.height ?? 1.15;
    final maxHeight = lines * maxSize * lineHeight;
    final plain = markdownToPlain(prompt);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var size = maxSize;
        if (width.isFinite) {
          // The largest size whose wrapped text fits into the reserved space.
          while (size > minFontSize) {
            final painter = TextPainter(
              text: TextSpan(text: plain, style: base.copyWith(fontSize: size)),
              textDirection: direction,
              textScaler: scaler,
            )..layout(maxWidth: width);
            final fits = painter.height <= maxHeight;
            painter.dispose();
            if (fits) break;
            size = (size - 2).clamp(minFontSize, maxSize);
          }
        }
        final text = QuizMarkdown(
          prompt,
          style: style?.copyWith(fontSize: size),
        );
        if (!width.isFinite) return text;
        // Safety net (Markdown emphasis is a little wider than the plain
        // text measured above): scale down, never clip.
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: text),
          ),
        );
      },
    );
  }
}
