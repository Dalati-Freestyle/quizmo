import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../core/data/session_checkpoint.dart';
import '../../../core/data/session_recovery.dart';

Future<SessionRecoveryStore> createRecoveryStore() async =>
    BrowserSessionRecoveryStore();

final class BrowserSessionRecoveryStore implements SessionRecoveryStore {
  static const _name = 'quizmo-host-recovery-v1';
  Completer<void>? _release;
  Future<JSAny?>? _lease;
  String? _quizDocument;

  @override
  Future<void> acquire() async {
    if (_lease != null) {
      throw const RecoveryException('Recovery is already open.');
    }
    _quizDocument = null;
    final ready = Completer<void>();
    final release = Completer<void>();
    try {
      _lease = web.window.navigator.locks
          .request(
            _name,
            web.LockOptions(ifAvailable: true),
            ((web.Lock? lock) {
              if (lock == null) {
                ready.completeError(
                  const RecoveryException(
                    'This game is open in another host. Close it before recovering.',
                  ),
                );
                return Future<JSAny?>.value(null).toJS;
              }
              _release = release;
              ready.complete();
              return release.future.then<JSAny?>((_) => null).toJS;
            }).toJS,
          )
          .toDart;
    } on Object {
      throw const RecoveryException(
        'Browser recovery needs HTTPS, IndexedDB and Web Locks. Allow site storage and retry.',
      );
    }
    unawaited(
      _lease!.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) {
            ready.completeError(
              const RecoveryException(
                'Browser recovery needs HTTPS, IndexedDB and Web Locks. Allow site storage and retry.',
              ),
            );
          }
        },
      ),
    );
    try {
      await ready.future;
    } on Object {
      _lease = null;
      rethrow;
    }
  }

  Future<web.IDBDatabase> _open() async {
    final web.IDBOpenDBRequest request;
    try {
      request = web.window.indexedDB.open(_name, 1);
    } on Object {
      throw const RecoveryException(
        'Cannot open recovery storage. Allow site storage.',
      );
    }
    final ready = Completer<web.IDBDatabase>();
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore('checkpoints');
    }).toJS;
    request.onsuccess = ((web.Event _) {
      if (ready.isCompleted) {
        (request.result as web.IDBDatabase).close();
        return;
      }
      ready.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      ready.completeError(
        const RecoveryException(
          'Cannot open recovery storage. Allow site storage.',
        ),
      );
    }).toJS;
    request.onblocked = ((web.Event _) {
      if (!ready.isCompleted) {
        ready.completeError(
          const RecoveryException(
            'Recovery storage is blocked. Close other Quizmo tabs and retry.',
          ),
        );
      }
    }).toJS;
    return ready.future;
  }

  Future<RecoveryRecord?> _transaction({
    String? contents,
    String? quizDocument,
    bool delete = false,
  }) async {
    final writing = contents != null || delete;
    if (writing && _release == null) {
      throw const RecoveryException('Recovery storage is not locked.');
    }
    final database = await _open();
    try {
      final transaction = database.transaction(
        'checkpoints'.toJS,
        writing ? 'readwrite' : 'readonly',
        web.IDBTransactionOptions(durability: 'strict'),
      );
      final done = Completer<RecoveryRecord?>();
      final store = transaction.objectStore('checkpoints');
      final request = delete
          ? store.clear()
          : contents != null
          ? store.put(contents.toJS, 'current'.toJS)
          : store.get('current'.toJS);
      String? result;
      String quiz = '';
      if (writing && !delete && _quizDocument != quizDocument) {
        store.put(quizDocument!.toJS, 'quiz'.toJS);
      } else if (!writing) {
        final quizRequest = store.get('quiz'.toJS);
        quizRequest.onsuccess = ((web.Event _) {
          if (quizRequest.result != null && !quizRequest.result.isUndefined) {
            quiz = (quizRequest.result as JSString).toDart;
          }
        }).toJS;
      }
      request.onsuccess = ((web.Event _) {
        if (!writing && request.result != null && !request.result.isUndefined) {
          result = (request.result as JSString).toDart;
        }
      }).toJS;
      transaction.oncomplete = ((web.Event _) {
        if (writing) _quizDocument = delete ? null : quizDocument;
        done.complete(
          result == null && quiz.isEmpty
              ? null
              : RecoveryRecord(result ?? '', quiz),
        );
      }).toJS;
      transaction.onabort = ((web.Event _) {
        if (!done.isCompleted) {
          done.completeError(
            const RecoveryException(
              'Recovery transaction failed. Check free space and allow site storage.',
            ),
          );
        }
      }).toJS;
      return await done.future;
    } finally {
      database.close();
    }
  }

  @override
  Future<RecoveryRecord?> read() => _transaction();
  @override
  Future<void> write(String contents, String quizDocument) async {
    await _transaction(contents: contents, quizDocument: quizDocument);
  }

  @override
  Future<void> delete() async {
    await _transaction(delete: true);
  }

  @override
  Future<void> release() async {
    _release?.complete();
    _release = null;
    await _lease;
    _lease = null;
  }
}
