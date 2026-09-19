/// Persistence contracts for the local quiz library.
library;

import 'dart:convert';

import '../models/models.dart';

/// Describes an unavailable or malformed local quiz library.
final class QuizRepositoryException implements Exception {
  /// Creates an exception with a message suitable for the host UI.
  const QuizRepositoryException(this.message);

  /// Human-readable explanation of the repository failure.
  final String message;

  @override
  String toString() => 'QuizRepositoryException: $message';
}

/// Reads and writes the opaque document that backs a [QuizRepository].
abstract interface class QuizLibraryStore {
  /// Reads the complete persisted library, or `null` before its first write.
  Future<String?> read();

  /// Replaces the complete persisted library with [contents].
  Future<void> write(String contents);
}

/// Stores and retrieves reusable quiz definitions.
abstract interface class QuizRepository {
  /// Loads every quiz in the local library in its saved order.
  Future<List<Quiz>> loadAll();

  /// Creates or replaces [quiz] by its stable ID.
  Future<void> save(Quiz quiz);

  /// Deletes the quiz identified by [quizId].
  Future<void> delete(String quizId);
}

/// Serializes a complete library through an injected [QuizLibraryStore].
final class PersistentQuizRepository implements QuizRepository {
  /// Creates a repository backed by [store].
  PersistentQuizRepository({required QuizLibraryStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final QuizLibraryStore _store;

  @override
  Future<List<Quiz>> loadAll() async {
    final contents = await _store.read();
    if (contents == null || contents.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) {
        throw const QuizRepositoryException(
          'The local quiz library is not a JSON object.',
        );
      }
      final json = Map<String, Object?>.from(decoded);
      final schemaVersion = json.readInt('schemaVersion');
      if (schemaVersion != _schemaVersion) {
        throw QuizRepositoryException(
          'Unsupported local library schemaVersion $schemaVersion. '
          'Expected $_schemaVersion.',
        );
      }
      return List.unmodifiable(json.readList('quizzes', Quiz.fromJson));
    } on QuizRepositoryException {
      rethrow;
    } on FormatException catch (error) {
      throw QuizRepositoryException(
        'The local quiz library contains invalid JSON: ${error.message}',
      );
    } on JsonContractException catch (error) {
      throw QuizRepositoryException(
        'The local quiz library is invalid: ${error.message}',
      );
    } on QuizValidationException catch (error) {
      throw QuizRepositoryException(
        'The local quiz library is invalid: ${error.messages.join(' ')}',
      );
    }
  }

  @override
  Future<void> save(Quiz quiz) async {
    quiz.validate();
    final quizzes = [...await loadAll()];
    final existingIndex = quizzes.indexWhere((item) => item.id == quiz.id);
    if (existingIndex < 0) {
      quizzes.add(quiz);
    } else {
      quizzes[existingIndex] = quiz;
    }
    await _write(quizzes);
  }

  @override
  Future<void> delete(String quizId) async {
    final quizzes = await loadAll();
    await _write(quizzes.where((quiz) => quiz.id != quizId).toList());
  }

  Future<void> _write(List<Quiz> quizzes) => _store.write(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': _schemaVersion,
      'quizzes': quizzes.map((quiz) => quiz.toJson()).toList(growable: false),
    }),
  );
}

/// Keeps quizzes in memory for tests and ephemeral previews.
final class InMemoryQuizRepository implements QuizRepository {
  /// Creates a repository initialized with [initialQuizzes].
  InMemoryQuizRepository([Iterable<Quiz> initialQuizzes = const []])
    : _quizzes = List<Quiz>.from(initialQuizzes);

  final List<Quiz> _quizzes;

  @override
  Future<List<Quiz>> loadAll() async => List.unmodifiable(_quizzes);

  @override
  Future<void> save(Quiz quiz) async {
    quiz.validate();
    final existingIndex = _quizzes.indexWhere((item) => item.id == quiz.id);
    if (existingIndex < 0) {
      _quizzes.add(quiz);
    } else {
      _quizzes[existingIndex] = quiz;
    }
  }

  @override
  Future<void> delete(String quizId) async {
    _quizzes.removeWhere((quiz) => quiz.id == quizId);
  }
}
