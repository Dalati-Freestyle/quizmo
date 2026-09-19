/// Browser file transfer for standalone quiz documents.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/data/quiz_import_export.dart';
import '../../../core/models/models.dart';

/// Describes a file that could not be transferred safely.
final class QuizFileTransferException implements Exception {
  /// Creates an exception with an actionable [message].
  const QuizFileTransferException(this.message);

  /// Human-readable explanation rendered in the quiz library.
  final String message;

  @override
  String toString() => 'QuizFileTransferException: $message';
}

const int _maxQuizFileBytes = 5 * 1024 * 1024;

/// Opens the browser picker and returns the selected quiz JSON, or `null` on cancel.
Future<String?> pickQuizJson() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Import Quizmo quiz',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  if (bytes.length > _maxQuizFileBytes) {
    throw const QuizFileTransferException(
      'The selected file is larger than the 5 MiB quiz import limit.',
    );
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const QuizFileTransferException(
      'The selected file is not valid UTF-8 text.',
    );
  }
}

/// Starts a browser download for [quiz] as a `*.quizmo.json` file.
Future<void> exportQuizFile(Quiz quiz) => SharePlus.instance.share(
  ShareParams(
    title: 'Export ${quiz.name}',
    files: [
      XFile.fromData(
        utf8.encode(exportQuizJson(quiz)),
        mimeType: 'application/json',
      ),
    ],
    fileNameOverrides: ['${_fileStem(quiz.name)}.quizmo.json'],
  ),
);

String _fileStem(String name) {
  final stem = name.trim().replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '-');
  return stem.isEmpty ? 'quiz' : stem;
}
