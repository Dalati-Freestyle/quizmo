/// Moves the quiz library from an older storage location to a new store.
library;

import 'quiz_repository.dart';

/// Reads the library from a new store and, until its first write, from a
/// legacy location.
///
/// The first save writes the complete library to the new store and only then
/// clears the legacy copy, so a library is never lost when the storage
/// changes: an interrupted migration simply reads the legacy copy again.
final class MigratingQuizLibraryStore implements QuizLibraryStore {
  /// Creates a store that migrates [legacy] into [store] on first save.
  ///
  /// [onRead] and [onWrite] observe the document, e.g. for backup reminders.
  MigratingQuizLibraryStore(
    QuizLibraryStore store, {
    required LegacyQuizLibrarySource legacy,
    void Function(String? contents)? onRead,
    void Function(String contents)? onWrite,
  }) : _store = store,
       _legacy = legacy,
       _onRead = onRead,
       _onWrite = onWrite;

  final QuizLibraryStore _store;
  final LegacyQuizLibrarySource _legacy;
  final void Function(String? contents)? _onRead;
  final void Function(String contents)? _onWrite;

  @override
  Future<String?> read() async {
    final contents = await _store.read() ?? await _legacy.read();
    _onRead?.call(contents);
    return contents;
  }

  @override
  Future<void> write(String contents) async {
    await _store.write(contents);
    try {
      await _legacy.clear();
    } on Object {
      // The new store is authoritative now; a stale legacy copy is unused.
    }
    _onWrite?.call(contents);
  }
}
