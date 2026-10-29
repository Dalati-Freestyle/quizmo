import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/editor/image_optimization_dialog.dart';
import 'package:quizmo/presentation/quizmaster/editor/media_editor.dart';

import 'media_upload_test.dart' show TestMediaFile, imageBytes;

class _Picker extends FilePickerPlatform {
  _Picker(this.file);

  final PlatformFile? file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => file;
}

void main() {
  late FilePickerPlatform originalPicker;

  setUp(() => originalPicker = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = originalPicker);

  Future<void> upload(
    WidgetTester tester,
    PlatformFile? file,
    ValueChanged<List<MediaAttachment>> onChanged,
  ) async {
    FilePickerPlatform.instance = _Picker(file);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaEditor(
              media: const [],
              onChanged: onChanged,
              title: 'Media',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload image'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('rejects oversized metadata before reading or publishing', (
    tester,
  ) async {
    final file = TestMediaFile(size: maxMediaBytes + 1);
    var changed = false;
    await upload(tester, file, (_) => changed = true);
    expect(file.read, isFalse);
    expect(changed, isFalse);
    expect(find.textContaining('20 MiB'), findsWidgets);
    expect(find.byType(ImageOptimizationDialog), findsNothing);
  });

  testWidgets('content validation rejects a renamed invalid image', (
    tester,
  ) async {
    final file = TestMediaFile(size: 8, bytes: Uint8List(8));
    var changed = false;
    await upload(tester, file, (_) => changed = true);
    expect(file.read, isTrue);
    expect(changed, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('canceling an image choice leaves attachments unchanged', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() => imageBytes(20, 10)))!;
    final file = TestMediaFile(size: bytes.length, bytes: bytes);
    var changed = false;
    await upload(tester, file, (_) => changed = true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.text('Keep original'), findsNothing);
  });

  testWidgets('original is published only after the explicit image choice', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() => imageBytes(20, 10)))!;
    final file = TestMediaFile(size: bytes.length, bytes: bytes);
    List<MediaAttachment>? changed;
    await upload(tester, file, (attachments) => changed = attachments);
    expect(changed, isNull);
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    expect(changed, hasLength(1));
    expect(
      (changed!.single as ImageAttachment).asset.bytes,
      orderedEquals(bytes),
    );
  });
}
