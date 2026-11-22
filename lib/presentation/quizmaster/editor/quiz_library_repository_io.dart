/// Native implementation of the local quiz library factory.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/quiz_library_store_io.dart';
import '../../../core/data/quiz_repository.dart';

const String _libraryKey = 'quizmo.quiz-library.v1';

/// Creates the persistent local quiz repository for native platforms.
///
/// The library lives in a file because quizzes embed their media; libraries
/// written to SharedPreferences by older versions are migrated on first save.
QuizRepository createQuizRepository() => PersistentQuizRepository(
  store: FileQuizLibraryStore(
    () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'quiz-library'),
    ),
    legacy: _SharedPreferencesLibrary(),
  ),
);

final class _SharedPreferencesLibrary implements LegacyQuizLibrarySource {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_libraryKey);

  @override
  Future<void> clear() => _preferences.remove(_libraryKey);
}
