import 'dart:async';

import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/data/session_recovery.dart';

class MemoryRecoveryStore implements SessionRecoveryStore {
  RecoveryRecord? record;
  bool locked = false;
  bool failWrites = false;
  int writes = 0;
  Completer<void>? writeBarrier;

  @override
  Future<RecoveryRecord?> read() async => record;
  @override
  Future<void> acquire() async {
    if (locked) throw const RecoveryException('Another host holds recovery.');
    locked = true;
  }

  @override
  Future<void> write(String contents, String quizDocument) async {
    if (!locked) throw StateError('Not locked');
    await writeBarrier?.future;
    if (failWrites) throw StateError('Disk full');
    record = RecoveryRecord(contents, quizDocument);
    writes++;
  }

  @override
  Future<void> delete() async {
    if (!locked) throw StateError('Not locked');
    record = null;
  }

  @override
  Future<void> release() async {
    locked = false;
  }
}
