/// IndexedDB storage for the quiz library in browsers.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../core/data/quiz_repository.dart';

const String _defaultDatabaseName = 'quizmo';
const String _objectStoreName = 'quiz-library';
const String _documentKey = 'library';

/// Persists the library document in the browser's IndexedDB.
///
/// Unlike `localStorage` (about 5 MB per site), IndexedDB may use a large
/// share of the free disk space, so libraries with embedded media fit. The
/// document is replaced in a single transaction: an interrupted write keeps
/// the previous library. After the first save the browser is asked to keep
/// the data when it frees up storage.
final class IndexedDbQuizLibraryStore implements QuizLibraryStore {
  /// Creates a store in the database [databaseName].
  IndexedDbQuizLibraryStore({String databaseName = _defaultDatabaseName})
    : _databaseName = databaseName;

  final String _databaseName;
  web.IDBDatabase? _database;
  bool _persistenceRequested = false;

  @override
  Future<String?> read() async {
    final database = await _open();
    final JSAny? result;
    try {
      final request = database
          .transaction(_objectStoreName.toJS, 'readonly')
          .objectStore(_objectStoreName)
          .get(_documentKey.toJS);
      result = await _completeRequest(request, 'read');
    } on QuizRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw _failure('read', error);
    }
    if (result == null) return null;
    if (!result.typeofEquals('string')) {
      throw const QuizRepositoryException(
        'The local quiz library in this browser is damaged.',
      );
    }
    return (result as JSString).toDart;
  }

  @override
  Future<void> write(String contents) async {
    final database = await _open();
    try {
      final transaction = database.transaction(
        _objectStoreName.toJS,
        'readwrite',
      );
      final done = _completeTransaction(transaction);
      transaction
          .objectStore(_objectStoreName)
          .put(contents.toJS, _documentKey.toJS);
      await done;
    } on QuizRepositoryException {
      rethrow;
    } on Object catch (error) {
      throw _failure('saved', error);
    }
    unawaited(_requestPersistence());
  }

  /// Closes the connection; the next access opens it again.
  void close() {
    _database?.close();
    _database = null;
  }

  Future<web.IDBDatabase> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final completer = Completer<web.IDBDatabase>();
    try {
      final request = web.window.indexedDB.open(_databaseName, 1);
      request.onupgradeneeded = ((web.Event _) {
        final database = request.result as web.IDBDatabase;
        if (!database.objectStoreNames.contains(_objectStoreName)) {
          database.createObjectStore(_objectStoreName);
        }
      }).toJS;
      request.onsuccess = ((web.Event _) {
        completer.complete(request.result as web.IDBDatabase);
      }).toJS;
      request.onerror = ((web.Event event) {
        event.preventDefault();
        completer.completeError(_domFailure('opened', request.error));
      }).toJS;
    } on Object catch (error) {
      completer.completeError(_failure('opened', error));
    }
    final database = await completer.future;
    // A newer Quizmo in another tab upgrades the database: let it.
    database.onversionchange = ((web.Event _) {
      database.close();
      if (identical(_database, database)) _database = null;
    }).toJS;
    return _database = database;
  }

  Future<void> _requestPersistence() async {
    if (_persistenceRequested) return;
    _persistenceRequested = true;
    try {
      final storage = web.window.navigator.storage;
      if (!(await storage.persisted().toDart).toDart) {
        await storage.persist().toDart;
      }
    } on Object {
      // Best effort: without it the browser may evict the data when the disk
      // runs full, which the export reminder on leaving covers.
    }
  }
}

Future<JSAny?> _completeRequest(web.IDBRequest request, String action) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(
    request.result,
  )).toJS;
  request.onerror = ((web.Event event) {
    event.preventDefault();
    completer.completeError(_domFailure(action, request.error));
  }).toJS;
  return completer.future;
}

Future<void> _completeTransaction(web.IDBTransaction transaction) {
  final completer = Completer<void>();
  transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
  void fail(web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(_domFailure('saved', transaction.error));
    }
  }

  transaction.onerror = fail.toJS;
  transaction.onabort = fail.toJS;
  return completer.future;
}

/// Explains an error IndexedDB reported through a request or transaction.
QuizRepositoryException _domFailure(
  String action,
  web.DOMException? exception,
) => _explain(
  action,
  exception?.name == 'QuotaExceededError',
  exception?.message ?? 'unknown error',
);

/// Explains an error thrown synchronously by the IndexedDB API.
QuizRepositoryException _failure(String action, Object error) =>
    _explain(action, '$error'.contains('QuotaExceededError'), '$error');

QuizRepositoryException _explain(String action, bool full, String detail) {
  if (full) {
    return const QuizRepositoryException(
      'The local quiz library cannot be saved: the browser storage is full. '
      'Free up disk space, delete quizzes with large media or use the Quizmo '
      'app for very large quizzes.',
    );
  }
  return QuizRepositoryException(
    'The local quiz library cannot be $action in this browser ($detail). '
    'Private windows and blocked site data prevent saving quizzes: allow site '
    'data for Quizmo or use the Quizmo app.',
  );
}
