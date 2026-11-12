import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/data/sample_quiz.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_cubit.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 22);

  test(
    'first launch persists all examples and reload does not duplicate them',
    () async {
      final store = _MemoryStore();
      final repository = PersistentQuizRepository(store: store);
      final cubit = QuizLibraryCubit(
        repository: repository,
        now: () => timestamp,
      );
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.error, isNull);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.quizzes, createSampleQuizzes(timestamp));
      expect(await repository.loadAll(), cubit.state.quizzes);

      await cubit.load();
      expect(cubit.state.quizzes, hasLength(3));
      final reopened = QuizLibraryCubit(
        repository: PersistentQuizRepository(store: store),
      );
      addTearDown(reopened.close);
      await reopened.load();
      expect(reopened.state.quizzes, cubit.state.quizzes);
    },
  );

  test(
    'existing libraries including edited or old demos remain untouched',
    () async {
      final existing = [
        createSampleQuiz(timestamp)
            .copyWith(name: 'Mein bearbeitetes Beispiel', questions: []),
        createSampleQuiz(timestamp)
            .copyWith(id: 'custom', name: 'Eigenes Quiz'),
      ];
      final repository = InMemoryQuizRepository(existing);
      final cubit = QuizLibraryCubit(repository: repository);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.quizzes, existing);
      expect(await repository.loadAll(), existing);
    },
  );

  test('deleting the last quiz restores all format examples', () async {
    final onlyQuiz = createSampleQuiz(timestamp).copyWith(id: 'custom');
    final repository = InMemoryQuizRepository([onlyQuiz]);
    final cubit = QuizLibraryCubit(
      repository: repository,
      now: () => timestamp,
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.delete(onlyQuiz);
    expect(cubit.state.error, isNull);
    expect(cubit.state.isBusy, isFalse);
    expect(cubit.state.quizzes, createSampleQuizzes(timestamp));
    expect(await repository.loadAll(), cubit.state.quizzes);
  });

  test(
    'deleting one demo does not restore it while other quizzes remain',
    () async {
      final examples = createSampleQuizzes(timestamp);
      final cubit = QuizLibraryCubit(
        repository: InMemoryQuizRepository(examples),
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.delete(examples.first);
      await cubit.load();
      expect(cubit.state.quizzes, examples.skip(1).toList());
    },
  );

  test('read failure does not seed over the library', () async {
    final cubit = QuizLibraryCubit(repository: _FailingRepository());
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.error, contains('Lesefehler'));
    expect(cubit.state.quizzes, isEmpty);
  });
}

class _MemoryStore implements QuizLibraryStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String contents) async => this.contents = contents;
}

class _FailingRepository implements QuizRepository {
  @override
  Future<void> recreateExamples(DateTime timestamp) async =>
      fail('Must not overwrite an unreadable library');
  @override
  Future<List<Quiz>> loadAll() async =>
      throw const QuizRepositoryException('Lesefehler');
  @override
  Future<void> save(Quiz quiz) async =>
      fail('Must not overwrite an unreadable library');
  @override
  Future<void> delete(String quizId) async => fail('Unexpected delete');
}
