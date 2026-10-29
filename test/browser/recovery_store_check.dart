import 'dart:async';
import 'dart:js_interop';

import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/presentation/quizmaster/recovery/recovery_store_web.dart';
import 'package:web/web.dart' as web;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  try {
    final first = BrowserSessionRecoveryStore();
    final second = BrowserSessionRecoveryStore();
    await first.acquire();
    try {
      await first.delete();
      await first.write('first checkpoint', 'quiz with embedded media');
      check(
        (await second.read())!.checkpoint == 'first checkpoint',
        'Snapshot must commit',
      );
      check(
        (await second.read())!.quiz == 'quiz with embedded media',
        'Media must commit',
      );
      var excluded = false;
      try {
        await second.acquire();
      } on RecoveryException {
        excluded = true;
      }
      check(excluded, 'Another host must be excluded');
      final opened = web.window.indexedDB.open('quizmo-host-recovery-v1', 1);
      final ready = Completer<web.IDBDatabase>();
      opened.onsuccess = ((web.Event _) => ready.complete(
        opened.result as web.IDBDatabase,
      )).toJS;
      final database = await ready.future;
      final aborted = Completer<void>();
      final transaction = database.transaction('checkpoints'.toJS, 'readwrite');
      transaction.onabort = ((web.Event _) => aborted.complete()).toJS;
      transaction
          .objectStore('checkpoints')
          .put('interrupted write'.toJS, 'current'.toJS);
      transaction.abort();
      await aborted.future;
      database.close();
      check(
        (await first.read())!.checkpoint == 'first checkpoint',
        'Aborted transaction must retain the previous snapshot',
      );
      await first.write('second checkpoint', 'quiz with embedded media');
      check(
        (await first.read())!.checkpoint == 'second checkpoint',
        'Replacement must commit',
      );
      await first.delete();
      check(
        await first.read() == null,
        'Explicit deletion must clear recovery',
      );
    } finally {
      await first.release();
    }
    await second.acquire();
    await second.release();
    web.document.body!.textContent = 'PASS: IndexedDB atomic commit, abort, media, deletion and exclusive Web Locks';
  } on Object catch (error) {
    web.document.body!.textContent = 'FAIL: $error';
    rethrow;
  }
}
