/// Tests for moving the quiz library to a new storage location.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/migrating_quiz_library_store.dart';
import 'package:quizmo/core/data/quiz_repository.dart';

void main() {
  test(
    'reads the legacy library until the first save, then clears it',
    () async {
      final target = _Memory();
      final legacy = _Legacy('{"old":true}');
      final observed = <String?>[];
      final store = MigratingQuizLibraryStore(
        target,
        legacy: legacy,
        onRead: observed.add,
        onWrite: observed.add,
      );

      expect(await store.read(), '{"old":true}');
      expect(target.document, isNull, reason: 'reading never migrates');

      await store.write('{"new":true}');
      expect(target.document, '{"new":true}');
      expect(legacy.document, isNull);
      expect(await store.read(), '{"new":true}');
      expect(observed, ['{"old":true}', '{"new":true}', '{"new":true}']);
    },
  );

  test('a failed save keeps the legacy library', () async {
    final legacy = _Legacy('{"old":true}');
    final store = MigratingQuizLibraryStore(
      _Memory(fail: true),
      legacy: legacy,
    );

    await expectLater(
      store.write('{"new":true}'),
      throwsA(isA<QuizRepositoryException>()),
    );
    expect(legacy.document, '{"old":true}');
    expect(await store.read(), '{"old":true}');
  });

  test('the new store wins over a stale legacy copy', () async {
    final store = MigratingQuizLibraryStore(
      _Memory()..document = '{"new":true}',
      legacy: _Legacy('{"stale":true}', failClear: true),
    );
    expect(await store.read(), '{"new":true}');
    // Clearing the legacy copy may fail without losing the save.
    await store.write('{"newer":true}');
    expect(await store.read(), '{"newer":true}');
  });
}

final class _Memory implements QuizLibraryStore {
  _Memory({this.fail = false});
  final bool fail;
  String? document;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const QuizRepositoryException('storage is full');
    document = contents;
  }
}

final class _Legacy implements LegacyQuizLibrarySource {
  _Legacy(this.document, {this.failClear = false});
  final bool failClear;
  String? document;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('blocked');
    document = null;
  }
}
