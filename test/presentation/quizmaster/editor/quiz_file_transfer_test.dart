import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_file_transfer.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_cubit.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_page.dart';

void main() {
  late FilePickerPlatform originalPicker;
  late _Picker picker;

  setUp(() {
    originalPicker = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = originalPicker);

  test(
    'saves an importable file containing media and a safe file name',
    () async {
      final asset = MediaAsset.upload(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]),
        'png',
      );
      final quiz = createSampleQuiz(DateTime.utc(2026)).copyWith(
        name: 'Quiz / Friday?',
        questions: [
          TrueFalseQuestion(
            id: 'media',
            prompt: 'Is this an image?',
            correctAnswer: true,
            solutionMedia: [ImageAttachment(asset: asset)],
          ),
        ],
      );
      expect(await exportQuizFile(quiz), isTrue);
      expect(picker.savedName, 'Quiz-Friday-.quizmo.json');
      expect(picker.savedMime, 'application/json');
      expect(parseQuizImport(utf8.decode(picker.savedBytes!)), quiz);
    },
  );

  test('save cancellation is reported to the screen', () async {
    picker.cancelSave = true;
    expect(await exportQuizFile(createSampleQuiz(DateTime.utc(2026))), isFalse);
  });

  test('picker cancellation returns no import document', () async {
    expect(await pickQuizJson(), isNull);
  });

  test('rejects an oversized file before reading its contents', () async {
    final file = _File(Uint8List(0), size: maxQuizFileBytes + 1);
    picker.file = file;
    await expectLater(pickQuizJson(), throwsA(isA<QuizImportException>()));
    expect(file.wasRead, isFalse);
  });

  test('picked bytes can be imported and preserve Unicode text', () async {
    final quiz = createSampleQuiz(DateTime.utc(2026))
        .copyWith(name: 'Grüße 🌍');
    picker.file = _File(utf8.encode(exportQuizJson(quiz)));
    expect(parseQuizImport((await pickQuizJson())!), quiz);
    expect(picker.extensions, ['json']);
  });

  test('a successful retry clears the update requirement', () async {
    final quiz = createSampleQuiz(DateTime.utc(2026));
    final repository = InMemoryQuizRepository([quiz]);
    final cubit = QuizLibraryCubit(
      repository: repository,
      createId: () => 'copy',
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.importContents(
      jsonEncode({'schemaVersion': Quiz.currentSchemaVersion + 1}),
    );
    expect(cubit.state.requiredSchemaVersion, Quiz.currentSchemaVersion + 1);
    expect(await repository.loadAll(), [quiz]);
    await cubit.importContents(exportQuizJson(quiz));
    expect(cubit.state.requiredSchemaVersion, isNull);
    expect(cubit.state.error, isNull);
    expect((await repository.loadAll()).length, 2);
  });

  testWidgets(
    'prompts to update for newer files and shows ordinary validation errors',
    (tester) async {
      final quiz = createSampleQuiz(DateTime.utc(2026));
      final repository = InMemoryQuizRepository([quiz]);
      picker.file = _File(
        utf8.encode(
          jsonEncode({'schemaVersion': Quiz.currentSchemaVersion + 1}),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: QuizLibraryPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Update Quizmo to import this quiz'), findsOneWidget);
      expect(
        find.textContaining('Update the app, then import this file again.'),
        findsOneWidget,
      );
      expect(await repository.loadAll(), [quiz]);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Update Quizmo to import this quiz'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      picker.file = _File(utf8.encode(jsonEncode({'schemaVersion': -1})));
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Update Quizmo to import this quiz'), findsNothing);
      expect(
        find.textContaining('Unsupported quiz schemaVersion -1'),
        findsOneWidget,
      );
      expect(await repository.loadAll(), [quiz]);
    },
  );
}

class _Picker extends FilePickerPlatform {
  PlatformFile? file;
  bool cancelSave = false;
  String? savedName;
  String? savedMime;
  Uint8List? savedBytes;
  List<String>? extensions;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    savedMime = mimeType;
    return cancelSave ? null : Uri.parse('content://saved-quiz');
  }

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
  }) async {
    extensions = allowedExtensions;
    return file;
  }
}

final class _File extends PlatformFile {
  _File(this.bytes, {this.size});
  final Uint8List bytes;
  final int? size;
  bool wasRead = false;

  @override
  String get name => 'import.quizmo.json';
  @override
  Uri get uri => Uri.parse('content://picked-quiz');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int lengthSync() => size ?? bytes.length;
  @override
  Future<int> length() async => lengthSync();
  @override
  Future<Uint8List> readAsBytes() async {
    wasRead = true;
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}
