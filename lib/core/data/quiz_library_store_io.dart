/// File backed storage for the local quiz library on `dart:io` platforms.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'quiz_repository.dart';

/// Persists the library document as a file in [directory].
///
/// Platform key/value stores are unsuitable for libraries with embedded
/// media: Android's SharedPreferences (DataStore) pushes the whole document
/// through a platform channel into the Java heap, which fails for quizzes of a
/// few hundred megabytes. A file has no such limit.
///
/// Writes go to a pending file that is renamed over the library, so an
/// interrupted write never corrupts the stored quizzes. Until the first write,
/// [legacy] supplies the document of the previous storage location; it is
/// cleared once the file has been written.
final class FileQuizLibraryStore implements QuizLibraryStore {
  /// Creates a store whose directory is resolved lazily on first access.
  FileQuizLibraryStore(this._directory, {LegacyQuizLibrarySource? legacy})
    : _legacy = legacy;

  final Future<Directory> Function() _directory;
  final LegacyQuizLibrarySource? _legacy;

  Future<File> _file(String name) async =>
      File(p.join((await _directory()).path, name));

  @override
  Future<String?> read() async {
    final File file;
    try {
      file = await _file('library.json');
      if (await file.exists()) return await file.readAsString();
    } on FileSystemException catch (error) {
      throw QuizRepositoryException(
        'The local quiz library cannot be read: ${error.message}',
      );
    }
    return _legacy?.read();
  }

  @override
  Future<void> write(String contents) async {
    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      final pending = File(p.join(directory.path, 'library.pending'));
      await pending.writeAsString(contents, flush: true);
      await pending.rename(p.join(directory.path, 'library.json'));
    } on FileSystemException catch (error) {
      throw QuizRepositoryException(
        'The local quiz library cannot be saved: ${error.message}. '
        'Check the free storage space.',
      );
    }
    try {
      await _legacy?.clear();
    } on Object {
      // The file is authoritative now; a stale legacy copy is only unused.
    }
  }
}
