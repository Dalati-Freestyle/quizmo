/// JSON import and export for standalone quiz files.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import 'quiz_repository.dart';

/// The maximum size of a complete quiz file, including encoded media.
const maxQuizFileBytes = 100 * 1024 * 1024;

/// Describes a quiz file that cannot be imported safely.
class QuizImportException implements Exception {
  /// Creates an exception with an actionable [message].
  const QuizImportException(this.message);

  /// Human-readable explanation rendered in the editor.
  final String message;

  @override
  String toString() => 'QuizImportException: $message';
}

/// An import that can be retried after updating Quizmo.
final class QuizImportUpdateRequiredException extends QuizImportException {
  /// Creates an update request with the required file schema version.
  const QuizImportUpdateRequiredException({
    required this.requiredSchemaVersion,
    required String message,
  }) : super(message);

  /// Schema version the installed app cannot yet import.
  final int requiredSchemaVersion;
}

/// Encodes [quiz] as one human-readable `*.quizmo.json` document.
///
/// Includes the schema version, solutions, and uploaded media as Base64.
String exportQuizJson(Quiz quiz) {
  quiz.validate();
  final contents = const JsonEncoder.withIndent('  ').convert(quiz.toJson());
  _checkFileSize(contents);
  return contents;
}

/// Decodes a picked file before parsing its versioned quiz document.
String decodeQuizFile(Uint8List bytes) {
  if (bytes.length > maxQuizFileBytes) {
    throw const QuizImportException(
      'The selected file is larger than the 100 MiB quiz import limit.',
    );
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const QuizImportException(
      'The selected file is not valid UTF-8 text.',
    );
  }
}

/// Parses and validates one standalone quiz document.
Quiz parseQuizImport(String contents) {
  _checkFileSize(contents);
  final Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException catch (error) {
    throw QuizImportException(
      'The selected file is not valid JSON: ${error.message}',
    );
  }
  try {
    if (decoded is! Map) {
      throw const QuizImportException(
        'The selected file must contain one quiz JSON object.',
      );
    }
    return Quiz.fromJson(Map<String, Object?>.from(decoded));
  } on QuizImportException {
    rethrow;
  } on FormatException catch (error) {
    throw QuizImportException(
      'The quiz file contains invalid encoded media: ${error.message}',
    );
  } on QuizSchemaUpdateRequiredException catch (error) {
    throw QuizImportUpdateRequiredException(
      requiredSchemaVersion: error.requiredVersion,
      message: error.message,
    );
  } on JsonContractException catch (error) {
    throw QuizImportException('The quiz file is invalid: ${error.message}');
  } on QuizValidationException catch (error) {
    throw QuizImportException(
      'The quiz file is invalid: ${error.messages.join(' ')}',
    );
  }
}

void _checkFileSize(String contents) {
  if (contents.length > maxQuizFileBytes ||
      utf8.encode(contents).length > maxQuizFileBytes) {
    throw const QuizImportException(
      'Quiz files must not exceed 100 MiB, including media.',
    );
  }
}

/// Validates [contents], resolves any ID collision, then persists the quiz.
Future<Quiz> importQuiz({
  required String contents,
  required QuizRepository repository,
  required String Function() createId,
  DateTime Function()? now,
}) async {
  final parsed = parseQuizImport(contents);
  final existingIds = (await repository.loadAll())
      .map((quiz) => quiz.id)
      .toSet();
  var imported = parsed;
  if (existingIds.contains(parsed.id)) {
    var id = createId();
    while (existingIds.contains(id)) {
      id = createId();
    }
    imported = parsed.copyWith(
      id: id,
      updatedAt: (now ?? DateTime.now)().toUtc(),
    );
  }
  await repository.save(imported);
  return imported;
}
