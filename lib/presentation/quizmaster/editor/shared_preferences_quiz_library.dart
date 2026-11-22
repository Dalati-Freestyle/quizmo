/// The quiz library location used by Quizmo up to version 1.3.2.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/quiz_repository.dart';

/// SharedPreferences key of the library written by older versions.
const String legacyQuizLibraryKey = 'quizmo.quiz-library.v1';

/// Reads and clears the library older versions kept in SharedPreferences
/// (the browser's `localStorage` on the web).
final class SharedPreferencesQuizLibrary implements LegacyQuizLibrarySource {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(legacyQuizLibraryKey);

  @override
  Future<void> clear() => _preferences.remove(legacyQuizLibraryKey);
}
