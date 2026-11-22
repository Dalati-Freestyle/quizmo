import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';

void main() {
  testWidgets('time limits of all questions change at once and stay editable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryQuizRepository();
    final quiz = Quiz(
      id: 'quiz',
      name: 'Bulk',
      description: 'Test',
      category: 'Test',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [
        TrueFalseQuestion(
          id: 'a',
          prompt: 'One?',
          correctAnswer: true,
          timeLimit: Duration(seconds: 10),
        ),
        ShortAnswerQuestion(
          id: 'b',
          prompt: 'Two?',
          acceptedAnswers: ['Two'],
          timeLimit: Duration.zero,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QuizEditorPage(
          repository: repository,
          quiz: quiz,
          createId: () => 'new',
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('bulk-edit')));
    await tester.tap(find.byKey(const ValueKey('bulk-edit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bulk-limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sekunden festlegen').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bulk-seconds')), '60');
    await tester.tap(find.byKey(const ValueKey('bulk-soft')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weich: Spielleitung beendet die Runde').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Gilt für 2 Fragen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save quiz'));
    await tester.pumpAndSettle();
    final saved = (await repository.loadAll()).single;
    for (final question in saved.questions) {
      expect(question.timeLimit, const Duration(seconds: 60));
      expect(question.softTimeLimit, isTrue);
    }
    expect(saved.questions.first.prompt, 'One?');
    expect(tester.takeException(), isNull);
  });
}
