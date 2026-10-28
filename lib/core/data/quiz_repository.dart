/// Persistence contracts for the local quiz library.
library;

import 'dart:convert';

import '../models/models.dart';
import 'sample_quiz.dart';

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

  /// Replaces unedited examples, preserving user quizzes and their stable IDs.
  Future<void> recreateExamples(DateTime timestamp);
}

/// Serializes a complete library through an injected [QuizLibraryStore].
final class PersistentQuizRepository implements QuizRepository {
  /// Creates a repository backed by [store].
  PersistentQuizRepository({required QuizLibraryStore store}) : _store = store;

  static const int _schemaVersion = 1;

  final QuizLibraryStore _store;

  @override
  Future<List<Quiz>> loadAll() async {
    return (await _read()).quizzes;
  }

  Future<({List<Quiz> quizzes, Set<String> defaultIds})> _read() async {
    final contents = await _store.read();
    if (contents == null || contents.trim().isEmpty) {
      return (quizzes: <Quiz>[], defaultIds: <String>{});
    }

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
      final quizzes = json.readList('quizzes', Quiz.fromJson);
      final defaultIds = json.containsKey('defaultQuizIds')
          ? json.readStringList('defaultQuizIds').toSet()
          : _legacyDefaultIds(quizzes);
      return (
        quizzes: List<Quiz>.unmodifiable(quizzes),
        defaultIds: defaultIds,
      );
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
    final library = await _read();
    final quizzes = [...library.quizzes];
    final existingIndex = quizzes.indexWhere((item) => item.id == quiz.id);
    if (existingIndex < 0) {
      quizzes.add(quiz);
    } else {
      quizzes[existingIndex] = quiz;
    }
    await _write(quizzes, library.defaultIds..remove(quiz.id));
  }

  @override
  Future<void> delete(String quizId) async {
    final library = await _read();
    await _write(
      library.quizzes.where((quiz) => quiz.id != quizId).toList(),
      library.defaultIds..remove(quizId),
    );
  }

  @override
  Future<void> recreateExamples(DateTime timestamp) async {
    final library = await _read();
    final replacement = _recreateExamples(
      library.quizzes,
      library.defaultIds,
      timestamp,
    );
    await _write(replacement.quizzes, replacement.defaultIds);
  }

  Future<void> _write(List<Quiz> quizzes, Set<String> defaultIds) =>
      _store.write(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': _schemaVersion,
          'quizzes': quizzes
              .map((quiz) => quiz.toJson())
              .toList(growable: false),
          'defaultQuizIds': defaultIds.toList(),
        }),
      );
}

/// Keeps quizzes in memory for tests and ephemeral previews.
final class InMemoryQuizRepository implements QuizRepository {
  /// Creates a repository initialized with [initialQuizzes].
  InMemoryQuizRepository([Iterable<Quiz> initialQuizzes = const []])
    : _quizzes = List<Quiz>.from(initialQuizzes),
      _defaultIds = _legacyDefaultIds(initialQuizzes);

  final List<Quiz> _quizzes;
  final Set<String> _defaultIds;

  @override
  Future<List<Quiz>> loadAll() async => List.unmodifiable(_quizzes);

  @override
  Future<void> save(Quiz quiz) async {
    quiz.validate();
    _defaultIds.remove(quiz.id);
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
    _defaultIds.remove(quizId);
  }

  @override
  Future<void> recreateExamples(DateTime timestamp) async {
    final replacement = _recreateExamples(_quizzes, _defaultIds, timestamp);
    _quizzes
      ..clear()
      ..addAll(replacement.quizzes);
    _defaultIds
      ..clear()
      ..addAll(replacement.defaultIds);
  }
}

Set<String> _legacyDefaultIds(Iterable<Quiz> quizzes) => {
  for (final quiz in quizzes)
    if (const {
          'quiz-sample',
          'quiz-sample-jeopardy',
          'quiz-sample-poker',
        }.contains(quiz.id) &&
        quiz.createdAt == quiz.updatedAt)
      quiz.id,
};

({List<Quiz> quizzes, Set<String> defaultIds}) _recreateExamples(
  List<Quiz> quizzes,
  Set<String> defaultIds,
  DateTime timestamp,
) {
  final retained = quizzes
      .where((quiz) => !defaultIds.contains(quiz.id))
      .toList();
  final usedIds = retained.map((quiz) => quiz.id).toSet();
  final examples = <Quiz>[];
  for (final example in createSampleQuizzes(timestamp)) {
    var id = example.id;
    var suffix = 1;
    while (!usedIds.add(id)) {
      id = '${example.id}-${suffix++}';
    }
    examples.add(example.copyWith(id: id));
  }
  return (
    quizzes: [...retained, ...examples],
    defaultIds: examples.map((quiz) => quiz.id).toSet(),
  );
}
