/// Native implementation of the local quiz library factory.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/quiz_repository.dart';

const String _libraryKey = 'quizmo.quiz-library.v1';

/// Creates the persistent local quiz repository for native platforms.
QuizRepository createQuizRepository() =>
    PersistentQuizRepository(store: _SharedPreferencesQuizLibraryStore());

final class _SharedPreferencesQuizLibraryStore implements QuizLibraryStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_libraryKey);

  @override
  Future<void> write(String contents) =>
      _preferences.setString(_libraryKey, contents);
}
