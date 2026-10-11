/// Unsupported-platform file transfer for standalone quiz documents.
library;

import '../../../core/models/models.dart';

/// Describes a file transfer that is unavailable on this platform.
final class QuizFileTransferException implements Exception {
  /// Creates an exception with an actionable [message].
  const QuizFileTransferException(this.message);

  /// Human-readable explanation rendered in the quiz library.
  final String message;

  @override
  String toString() => 'QuizFileTransferException: $message';
}

/// Throws because importing quiz files is unsupported on this platform.
Future<String?> pickQuizJson({
  String dialogTitle = 'Import Quizmo quiz (including media)',
}) => throw const QuizFileTransferException(
  'Importing quiz files is unavailable on this platform.',
);

/// Throws because exporting quiz files is unsupported on this platform.
Future<bool> exportQuizFile(
  Quiz quiz, {
  String dialogTitle = 'Export Quizmo quiz (including media)',
}) => throw const QuizFileTransferException(
  'Exporting quiz files is unavailable on this platform.',
);
