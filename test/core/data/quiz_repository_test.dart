/// Unit tests for the local quiz repository.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
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

  for (final persistent in [false, true]) {
    group(persistent ? 'persistent examples' : 'in-memory examples', () {
      late QuizRepository repository;
      late _MemoryStore store;
      final timestamp = DateTime.utc(2026, 10, 28);

      setUp(() {
        store = _MemoryStore();
        repository = persistent
            ? PersistentQuizRepository(store: store)
            : InMemoryQuizRepository();
      });

      test(
        'recreates all defaults without duplicates and restores deleted ones',
        () async {
          await repository.recreateExamples(timestamp);
          final original = await repository.loadAll();
          expect(original, createSampleQuizzes(timestamp));
          await repository.delete(original.first.id);
          final later = timestamp.add(const Duration(days: 1));
          await repository.recreateExamples(later);
          expect(await repository.loadAll(), createSampleQuizzes(later));
          await repository.recreateExamples(later);
          expect(await repository.loadAll(), createSampleQuizzes(later));
        },
      );

      test('saved examples become normal quizzes and keep their stable IDs', () async {
        await repository.recreateExamples(timestamp);
        final original = (await repository.loadAll()).first;
        // Even a save within the same clock tick must protect the user's work.
        final edited = original.copyWith(name: 'My edited example');
        await repository.save(edited);
        final custom = quiz(id: 'quiz-sample-1');
        await repository.save(custom);
        if (persistent) {
          repository = PersistentQuizRepository(store: store);
        }
        await repository.recreateExamples(timestamp);
        final restored = await repository.loadAll();
        expect(restored, hasLength(5));
        expect(restored, containsAll([edited, custom]));
        final fresh = restored.singleWhere(
          (item) => item.name == original.name,
        );
        expect(fresh.id, 'quiz-sample-2');
        await repository.recreateExamples(timestamp);
        expect(await repository.loadAll(), restored);

        await repository.save(fresh.copyWith(description: 'Another edit'));
        await repository.recreateExamples(timestamp);
        expect(await repository.loadAll(), hasLength(6));
        expect(
          (await repository.loadAll()).where(
            (item) => item.description == 'Another edit',
          ),
          hasLength(1),
        );
      });
    });
  }

  test(
    'legacy defaults are replaced but previously edited examples survive',
    () async {
      final timestamp = DateTime.utc(2026, 10, 22);
      final examples = createSampleQuizzes(timestamp);
      final edited = examples.first.copyWith(
        name: 'Previously edited',
        updatedAt: timestamp.add(const Duration(seconds: 1)),
      );
      final store = _MemoryStore()
        ..contents = jsonEncode({
          'schemaVersion': 1,
          'quizzes': [
            edited,
            ...examples.skip(1),
          ].map((quiz) => quiz.toJson()).toList(),
        });
      final repository = PersistentQuizRepository(store: store);
      await repository.recreateExamples(timestamp);
      final quizzes = await repository.loadAll();
      expect(quizzes, hasLength(4));
      expect(quizzes.first, edited);
      expect(quizzes.map((quiz) => quiz.id).toSet(), hasLength(4));
    },
  );

  test(
    'a failed recreation write leaves the persisted library untouched',
    () async {
      final store = _MemoryStore();
      final repository = PersistentQuizRepository(store: store);
      await repository.save(quiz());
      final before = store.contents;
      store.failWrites = true;
      await expectLater(
        repository.recreateExamples(DateTime.utc(2026, 10, 28)),
        throwsA(isA<QuizRepositoryException>()),
      );
      expect(store.contents, before);
      expect(await repository.loadAll(), [quiz()]);
    },
  );

  group('quizzes saved by a newer Quizmo', () {
    Map<String, Object?> newerQuiz(String id) => {
      ...quiz(id: id, name: 'From the future').toJson(),
      'schemaVersion': Quiz.currentSchemaVersion + 1,
      'futureField': {'kept': true},
    };

    test('older quizzes are migrated while newer ones are kept', () async {
      final legacy = {...quiz(id: 'legacy').toJson(), 'schemaVersion': 10};
      final future = newerQuiz('future');
      final store = _MemoryStore()
        ..contents = jsonEncode({
          'schemaVersion': 1,
          'quizzes': [legacy, future],
        });
      final repository = PersistentQuizRepository(store: store);

      final loaded = await repository.loadAll();
      expect(loaded.map((quiz) => quiz.id), ['legacy']);
      expect(loaded.single.schemaVersion, Quiz.currentSchemaVersion);
      expect(
        await repository.newerSchemaVersion(),
        Quiz.currentSchemaVersion + 1,
      );

      await repository.save(quiz(id: 'new'));
      await repository.delete('legacy');
      await repository.recreateExamples(DateTime.utc(2026, 11, 18));

      final stored =
          (jsonDecode(store.contents!) as Map<String, Object?>)['quizzes']!
              as List<Object?>;
      expect(stored, anyElement(equals(future)));
      expect(
        (await repository.loadAll()).map((quiz) => quiz.id),
        isNot(contains('legacy')),
      );
    });

    test('examples never reuse the ID of a hidden quiz', () async {
      final store = _MemoryStore()
        ..contents = jsonEncode({
          'schemaVersion': 1,
          'quizzes': [newerQuiz('quiz-sample')],
        });
      final repository = PersistentQuizRepository(store: store);
      await repository.recreateExamples(DateTime.utc(2026, 11, 18));
      expect(
        (await repository.loadAll()).map((quiz) => quiz.id),
        isNot(contains('quiz-sample')),
      );
      await expectLater(
        repository.save(quiz(id: 'quiz-sample')),
        throwsA(isA<QuizRepositoryException>()),
      );
    });

    test('a fully readable library reports no newer schema', () async {
      final repository = PersistentQuizRepository(store: _MemoryStore());
      await repository.save(quiz());
      expect(await repository.newerSchemaVersion(), isNull);
    });
  });

  test('malformed libraries are never overwritten by recreation', () async {
    final store = _MemoryStore()..contents = 'not JSON';
    final repository = PersistentQuizRepository(store: store);
    await expectLater(
      repository.recreateExamples(DateTime.utc(2026, 10, 28)),
      throwsA(isA<QuizRepositoryException>()),
    );
    expect(store.contents, 'not JSON');
  });
}

final class _MemoryStore implements QuizLibraryStore {
  String? contents;
  bool failWrites = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    if (failWrites) throw const QuizRepositoryException('Storage unavailable');
    this.contents = contents;
  }
}
