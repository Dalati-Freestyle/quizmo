/// JSON import and export for standalone quiz files.
library;

import 'dart:convert';

import '../models/models.dart';
import 'quiz_repository.dart';

/// Describes a quiz file that cannot be imported safely.
final class QuizImportException implements Exception {
  /// Creates an exception with an actionable [message].
  const QuizImportException(this.message);

  /// Human-readable explanation rendered in the editor.
  final String message;

  @override
  String toString() => 'QuizImportException: $message';
}

/// Encodes [quiz] as one human-readable `*.quizmo.json` document.
String exportQuizJson(Quiz quiz) {
  quiz.validate();
  return const JsonEncoder.withIndent('  ').convert(quiz.toJson());
}

/// Parses and validates one standalone quiz document.
Quiz parseQuizImport(String contents) {
  try {
    final decoded = jsonDecode(contents);
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
      'The selected file is not valid JSON: ${error.message}',
    );
  } on JsonContractException catch (error) {
    throw QuizImportException('The quiz file is invalid: ${error.message}');
  } on QuizValidationException catch (error) {
    throw QuizImportException(
      'The quiz file is invalid: ${error.messages.join(' ')}',
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
