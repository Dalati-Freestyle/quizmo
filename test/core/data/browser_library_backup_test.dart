import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/browser_library_backup.dart';

void main() {
  test('empty library needs no backup, custom quizzes do', () {
    expect(browserLibraryNeedsBackup(null), isFalse);
    expect(browserLibraryNeedsBackup('{"quizzes":[]}'), isFalse);
    expect(browserLibraryNeedsBackup('{"quizzes":[{"id":"custom"}]}'), isTrue);
  });
  test('unchanged demo needs no backup but edited demo does', () {
    expect(
      browserLibraryNeedsBackup(
        jsonEncode({
          'quizzes': [
            {'id': 'quiz-sample', 'createdAtMicros': 1, 'updatedAtMicros': 1},
          ],
        }),
      ),
      isFalse,
    );
    expect(
      browserLibraryNeedsBackup(
        jsonEncode({
          'quizzes': [
            {'id': 'quiz-sample', 'createdAtMicros': 1, 'updatedAtMicros': 2},
          ],
        }),
      ),
      isTrue,
    );
  });
  test('SharedPreferences encoding survives reload; malformed data warns', () {
    expect(
      browserLibraryNeedsBackup(
        jsonEncode(
          jsonEncode({
            'quizzes': [
              {'id': 'custom'},
            ],
          }),
        ),
      ),
      isTrue,
    );
    expect(browserLibraryNeedsBackup('damaged library'), isTrue);
  });
}
