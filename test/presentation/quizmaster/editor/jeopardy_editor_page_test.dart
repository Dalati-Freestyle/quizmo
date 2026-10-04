/// Widget test for building a Jeopardy quiz in the editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_page.dart';

void main() {
  testWidgets('creates a Jeopardy quiz and fills a cell with a buzzer question', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = InMemoryQuizRepository();
    var counter = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: QuizLibraryPage(
          repository: repository,
          createId: () => 'id-${counter++}',
          now: () => DateTime.utc(2026, 9, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Create quiz'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jeopardy'));
    await tester.pumpAndSettle();
    expect(find.text('Jeopardy board'), findsOneWidget);

    // Fill the first cell with a buzzer question.
    await tester.tap(find.text('Add question').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast buzzer'));
    await tester.pumpAndSettle();
    // The row decides the points, so the scoring rule is not offered.
    expect(find.text('Scoring rule'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'Who painted it?');
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save quiz'));
    await tester.pumpAndSettle();

    final saved = (await repository.loadAll()).singleWhere(
      (quiz) => quiz.id == 'id-0',
    );
    expect(saved.format, isA<JeopardyFormat>());
    expect(saved.questions.single.prompt, 'Who painted it?');
    final board = (saved.format as JeopardyFormat).board;
    expect(board.cellAt(0, 0).questionId, saved.questions.single.id);
  });
}

