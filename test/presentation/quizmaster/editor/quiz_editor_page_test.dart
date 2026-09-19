/// Widget tests for the quiz editor flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_page.dart';

void main() {
  testWidgets('adds a question and finds it after saving the quiz', (
    tester,
  ) async {
    final repository = InMemoryQuizRepository();
    final ids = ['quiz-widget-test', 'question-widget-test'].iterator;

    await tester.pumpWidget(
      MaterialApp(
        home: QuizLibraryPage(
          repository: repository,
          createId: () {
            ids.moveNext();
            return ids.current;
          },
          now: () => DateTime.utc(2026, 9, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Create quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add multiple-choice question'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Question added from widget test',
    );
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save quiz'));
    await tester.pumpAndSettle();

    final savedQuiz = (await repository.loadAll()).singleWhere(
      (quiz) => quiz.id == 'quiz-widget-test',
    );
    expect(
      savedQuiz.questions.single.prompt,
      'Question added from widget test',
    );
    expect(
      find.text('First question: Question added from widget test'),
      findsOneWidget,
    );
  });
}
