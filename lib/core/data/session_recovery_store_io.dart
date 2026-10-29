import 'dart:io';

import 'package:path/path.dart' as p;

import 'session_checkpoint.dart';
import 'session_recovery.dart';

final class FileSessionRecoveryStore implements SessionRecoveryStore {
  FileSessionRecoveryStore(this.directory);
  final Directory directory;
  File get _file => File(p.join(directory.path, 'session.json'));
  File get _temporary => File(p.join(directory.path, 'session.pending'));
  File get _quiz => File(p.join(directory.path, 'quiz.json'));
  File get _pendingQuiz => File(p.join(directory.path, 'quiz.pending'));
  String? _quizDocument;
  RandomAccessFile? _lock;
  static final _heldPaths = <String>{};

  @override
  Future<RecoveryRecord?> read() async {
    final hasSnapshot = await _file.exists();
    final hasQuiz = await _quiz.exists();
    if (!hasSnapshot &&
        !hasQuiz &&
        !await _temporary.exists() &&
        !await _pendingQuiz.exists()) {
      return null;
    }
    return RecoveryRecord(
      hasSnapshot ? await _file.readAsString() : '',
      hasQuiz ? await _quiz.readAsString() : '',
    );
  }

  @override
  Future<void> acquire() async {
    if (_lock != null) {
      throw const RecoveryException('Recovery is already open.');
    }
    final path = p.canonicalize(directory.absolute.path);
    if (!_heldPaths.add(path)) {
      throw const RecoveryException(
        'This game is open in another host. Close it before recovering.',
      );
    }
    final RandomAccessFile lock;
    try {
      await directory.create(recursive: true);
      lock = await File(p.join(directory.path, 'session.lock'))
          .open(mode: FileMode.append);
    } on FileSystemException {
      _heldPaths.remove(path);
      throw const RecoveryException(
        'Recovery storage cannot be opened. Check free space and storage permissions.',
      );
    }
    try {
      await lock.lock(FileLock.exclusive);
      _lock = lock;
      _quizDocument = null;
    } on FileSystemException {
      _heldPaths.remove(path);
      await lock.close();
      throw const RecoveryException(
        'This game is open in another host. Close it before recovering.',
      );
    }
  }

  void _requireLock() {
    if (_lock == null) {
      throw const RecoveryException('Recovery storage is not locked.');
    }
  }

  @override
  Future<void> write(String contents, String quizDocument) async {
    _requireLock();
    _quizDocument ??= await _quiz.exists() ? await _quiz.readAsString() : null;
    if (_quizDocument != quizDocument) {
      if (await _file.exists()) {
        throw const RecoveryException(
          'Cannot replace the quiz of an existing saved game.',
        );
      }
      await _pendingQuiz.writeAsString(quizDocument, flush: true);
      await _pendingQuiz.rename(_quiz.path);
      _quizDocument = quizDocument;
    }
    await _temporary.writeAsString(contents, flush: true);
    await _temporary.rename(_file.path);
  }

  @override
  Future<void> delete() async {
    _requireLock();
    if (await _file.exists()) await _file.delete();
    if (await _temporary.exists()) await _temporary.delete();
    if (await _quiz.exists()) await _quiz.delete();
    if (await _pendingQuiz.exists()) await _pendingQuiz.delete();
    _quizDocument = null;
  }

  @override
  Future<void> release() async {
    final lock = _lock;
    _lock = null;
    if (lock != null) {
      await lock.unlock();
      await lock.close();
      _heldPaths.remove(p.canonicalize(directory.absolute.path));
    }
  }
}
