import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/settings/example_quiz_settings.dart';

void main() {
  testWidgets('cancels or recreates examples and refreshes the library', (
    tester,
  ) async {
    final repository = InMemoryQuizRepository();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExampleQuizSettings(
            repository: repository,
            onChanged: () async => refreshes++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Recreate example quizzes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await repository.loadAll(), isEmpty);
    expect(refreshes, 0);

    await tester.tap(find.text('Recreate example quizzes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Recreate example quizzes'),
    );
    await tester.pumpAndSettle();
    expect(await repository.loadAll(), hasLength(3));
    expect(refreshes, 1);
    expect(find.text('Example quizzes recreated.'), findsOneWidget);
  });

  testWidgets('reports storage failure without claiming success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExampleQuizSettings(repository: _FailingRepository()),
        ),
      ),
    );
    await tester.tap(find.text('Recreate example quizzes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Recreate example quizzes'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    expect(find.text('Example quizzes recreated.'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
  });
}

class _FailingRepository implements QuizRepository {
  @override
  Future<void> recreateExamples(DateTime timestamp) async =>
      throw const QuizRepositoryException('Storage unavailable');

  @override
  Future<List<Quiz>> loadAll() async => [];

  @override
  Future<void> save(Quiz quiz) async => fail('Unexpected save');

  @override
  Future<void> delete(String quizId) async => fail('Unexpected delete');
}
