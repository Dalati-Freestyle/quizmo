/// Native implementation of the local quiz library factory.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/data/quiz_library_store_io.dart';
import '../../../core/data/quiz_repository.dart';
import 'shared_preferences_quiz_library.dart';

/// Creates the persistent local quiz repository for native platforms.
///
/// The library lives in a file because quizzes embed their media; libraries
/// written to SharedPreferences by older versions are migrated on first save.
QuizRepository createQuizRepository() => PersistentQuizRepository(
  store: FileQuizLibraryStore(
    () async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'quiz-library'),
    ),
    legacy: SharedPreferencesQuizLibrary(),
  ),
);
