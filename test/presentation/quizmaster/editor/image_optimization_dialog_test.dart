import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/editor/image_optimization_dialog.dart';

import 'media_upload_test.dart' show imageBytes;

void main() {
  Future<void> open(
    WidgetTester tester,
    MediaAsset original,
    ValueChanged<MediaAsset?> onSelected,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => onSelected(
                await showDialog<MediaAsset>(
                  context: context,
                  builder: (_) => ImageOptimizationDialog(original: original),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the original byte-for-byte without opting in', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() => imageBytes(100, 50));
    final original = MediaAsset.upload(bytes!, 'png');
    MediaAsset? selected;
    await open(tester, original, (asset) => selected = asset);
    expect(find.text('Use optimized copy'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    expect(selected, same(original));
    expect(selected!.bytes, orderedEquals(bytes));
  });

  testWidgets('preview never selects the copy automatically', (tester) async {
    final bytes = await tester.runAsync(() => imageBytes(100, 50));
    final original = MediaAsset.upload(bytes!, 'png');
    MediaAsset? selected;
    await open(tester, original, (asset) => selected = asset);
    await tester.ensureVisible(find.text('Preview optimized PNG copy'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Preview optimized PNG copy'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.textContaining('This PNG copy is not smaller'), findsOneWidget);
    final choose = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Use optimized copy'),
    );
    expect(choose.onPressed, isNull);
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    expect(selected, same(original));
  });

  testWidgets('requires explicit selection of a smaller optimized copy', (
    tester,
  ) async {
    final png = (await tester.runAsync(() => imageBytes(100, 50)))!;
    final bytes = Uint8List(png.length + 4096)..setAll(0, png);
    final original = MediaAsset.upload(bytes, 'png');
    MediaAsset? selected;
    await open(tester, original, (asset) => selected = asset);
    await tester.ensureVisible(find.text('Preview optimized PNG copy'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Preview optimized PNG copy'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Use optimized copy'));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(selected!.id, isNot(original.id));
    expect(selected!.mimeType, 'image/png');
    expect(selected!.bytes!.length, lessThan(bytes.length));
    expect(original.bytes, orderedEquals(bytes));
  });
}
