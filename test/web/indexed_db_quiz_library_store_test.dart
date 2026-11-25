/// Browser tests for the IndexedDB quiz library store.
///
/// Run with `flutter test --platform chrome test/web`.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/quizmaster/editor/indexed_db_quiz_library_store.dart';

void main() {
  test('stores a library far beyond the localStorage limit', () async {
    final name = 'quizmo-test-${DateTime.now().microsecondsSinceEpoch}';
    final store = IndexedDbQuizLibraryStore(databaseName: name);
    expect(await store.read(), isNull);

    // localStorage refuses about 5 MB; 24 MB of characters is ~48 MB in UTF-16.
    final large = '{"media":"${'x' * (24 * 1024 * 1024)}"}';
    await store.write(large);
    store.close();

    final reopened = IndexedDbQuizLibraryStore(databaseName: name);
    final read = await reopened.read();
    expect(read?.length, large.length);
    expect(read, large);

    await reopened.write('{"small":true}');
    expect(await reopened.read(), '{"small":true}');
    reopened.close();
  });
}
