/// Browser implementation of the local quiz library factory.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/quiz_repository.dart';
import '../../common/browser_exit_guard.dart';

const String _libraryKey = 'quizmo.quiz-library.v1';

/// Creates the browser-local persistent quiz repository.
QuizRepository createQuizRepository() =>
    PersistentQuizRepository(store: _SharedPreferencesQuizLibraryStore());

final class _SharedPreferencesQuizLibraryStore implements QuizLibraryStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() async {
    final contents = await _preferences.getString(_libraryKey);
    updateBrowserExitGuard(contents);
    return contents;
  }

  @override
  Future<void> write(String contents) async {
    await _preferences.setString(_libraryKey, contents);
    updateBrowserExitGuard(contents);
  }
}
