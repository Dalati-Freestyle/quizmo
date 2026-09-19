/// Unit tests for the local quiz repository.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  Quiz quiz({String id = 'quiz-1', String name = 'Original'}) => Quiz(
    id: id,
    name: name,
    description: 'Description',
    category: 'General knowledge',
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  test('saves, loads, overwrites, and deletes a quiz', () async {
    final store = _MemoryStore();
    final repository = PersistentQuizRepository(store: store);
    final original = quiz();

    await repository.save(original);
    expect(await repository.loadAll(), [original]);

    final replacement = original.copyWith(
      name: 'Updated',
      updatedAt: DateTime.utc(2026, 9, 20),
    );
    await repository.save(replacement);
    expect(await repository.loadAll(), [replacement]);

    await repository.delete(replacement.id);
    expect(await repository.loadAll(), isEmpty);
  });
}

final class _MemoryStore implements QuizLibraryStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    this.contents = contents;
  }
}
