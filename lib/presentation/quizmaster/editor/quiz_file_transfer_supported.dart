/// File picker transfers shared by native and browser platforms.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../../../core/data/quiz_import_export.dart';
import '../../../core/models/models.dart';

/// Opens a picker and returns a quiz document, or `null` on cancel.
Future<String?> pickQuizJson() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Import Quizmo quiz (including media)',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;
  if ((await file.length() ?? 0) > maxQuizFileBytes) {
    throw const QuizImportException(
      'The selected file is larger than the 100 MiB quiz import limit.',
    );
  }
  return decodeQuizFile(await file.readAsBytes());
}

/// Saves or downloads a complete quiz file, returning `false` on cancel.
Future<bool> exportQuizFile(Quiz quiz) async {
  final saved = await FilePicker.saveFile(
    dialogTitle: 'Export Quizmo quiz (including media)',
    fileName: '${_fileStem(quiz.name)}.quizmo.json',
    bytes: utf8.encode(exportQuizJson(quiz)),
    mimeType: 'application/json',
  );
  return saved != null;
}

String _fileStem(String name) {
  final stem = name.trim().replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '-');
  return stem.isEmpty ? 'quiz' : stem;
}
