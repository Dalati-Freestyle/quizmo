import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/browser_library_backup.dart';
import 'package:quizmo/core/data/sample_quiz.dart';

void main() {
  test('all untouched format demos need no backup; editing any one does', () {
    final examples = createSampleQuizzes(DateTime.utc(2026));
    expect(
      browserLibraryNeedsBackup(
        jsonEncode({'quizzes': examples.map((q) => q.toJson()).toList()}),
      ),
      isFalse,
    );
    for (final example in examples) {
      final edited = example.copyWith(updatedAt: DateTime.utc(2026, 2));
      expect(
        browserLibraryNeedsBackup(
          jsonEncode({
            'quizzes': examples
                .map((q) => (q.id == edited.id ? edited : q).toJson())
                .toList(),
          }),
        ),
        isTrue,
      );
    }
  });

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
