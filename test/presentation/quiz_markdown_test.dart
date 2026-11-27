import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/common/quiz_markdown.dart';
import 'package:quizmo/presentation/quizmaster/editor/markdown_field.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Form(child: child)),
    ),
  );

  TextSpan spanOf(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text).last).textSpan! as TextSpan;

  testWidgets('formats, reads plain text out and never opens links', (
    tester,
  ) async {
    await show(
      tester,
      const QuizMarkdown('**Fett** und [Link](https://x.de) <b>x</b>'),
    );
    final spans = spanOf(tester).children!.cast<TextSpan>();
    expect(spans.first.style!.fontWeight, FontWeight.w700);
    expect(spans.where((s) => s.recognizer != null), isEmpty);
    expect(
      tester.widget<Text>(find.byType(Text).last).semanticsLabel,
      'Fett und Link <b>x</b>',
    );
    await show(
      tester,
      const QuizMarkdown(
        '[Link](https://x.de) [Böse](javascript:x)',
        openLinks: true,
      ),
    );
    final linked = spanOf(tester).children!.cast<TextSpan>();
    expect(linked.where((s) => s.recognizer != null), hasLength(1));
    await show(tester, const QuizMarkdown('* unvollständig **'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain text looks like before', (tester) async {
    const style = TextStyle(fontSize: 20);
    await show(tester, const QuizMarkdown('Einfach nur Text', style: style));
    final text = tester.widget<Text>(find.byType(Text).last);
    expect(text.style, style);
    expect(text.textSpan!.toPlainText(), 'Einfach nur Text');
  });

  testWidgets('toolbar, shortcut and preview keep the input', (tester) async {
    final controller = TextEditingController(text: 'Hallo Welt');
    addTearDown(controller.dispose);
    await show(tester, MarkdownField(controller: controller, label: 'Prompt'));
    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 10);
    await tester.tap(find.byTooltip('Fett (Strg+B)'));
    await tester.pump();
    expect(controller.text, 'Hallo **Welt**');
    await tester.tap(find.byTooltip('Fett (Strg+B)'));
    await tester.pump();
    expect(controller.text, 'Hallo Welt', reason: 'a second press removes it');
    await tester.tap(find.byTooltip('Liste'));
    await tester.pump();
    expect(controller.text, '- Hallo Welt');
    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('markdown-preview')), findsOneWidget);
    expect(find.textContaining('• Hallo Welt'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('markdown-preview-toggle')));
    await tester.pump();
    expect(controller.text, '- Hallo Welt');
  });
}
