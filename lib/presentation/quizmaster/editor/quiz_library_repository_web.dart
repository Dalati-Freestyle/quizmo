/// Browser implementation of the local quiz library factory.
library;

import '../../../core/data/migrating_quiz_library_store.dart';
import '../../../core/data/quiz_repository.dart';
import '../../common/browser_exit_guard.dart';
import 'indexed_db_quiz_library_store.dart';
import 'shared_preferences_quiz_library.dart';

/// Creates the browser-local persistent quiz repository.
///
/// The library lives in IndexedDB because quizzes embed their media and
/// `localStorage` only holds a few megabytes. Libraries written to
/// `localStorage` by older versions are migrated on first save.
QuizRepository createQuizRepository() => PersistentQuizRepository(
  store: MigratingQuizLibraryStore(
    IndexedDbQuizLibraryStore(),
    legacy: SharedPreferencesQuizLibrary(),
    onRead: updateBrowserExitGuard,
    onWrite: updateBrowserExitGuard,
  ),
);
