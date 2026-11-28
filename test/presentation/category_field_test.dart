import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/category_field.dart';
import 'package:quizmo/presentation/quizmaster/editor/slides_editor_panel.dart';

final quiz = Quiz(
  id: 'q',
  name: 'Quiz',
  description: 'Kategorien',
  category: 'Test',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: const [
    TrueFalseQuestion(
      id: 'q1',
      prompt: 'A?',
      category: 'Geschichte',
      correctAnswer: true,
    ),
    TrueFalseQuestion(
      id: 'q2',
      prompt: 'B?',
      category: 'Biologie',
      correctAnswer: true,
    ),
  ],
);

void main() {
  testWidgets('an existing category is picked from the menu', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryField(
            controller: controller,
            categories: quiz.categories,
            label: 'Kategorie',
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('category-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Geschichte'), findsOneWidget);
    await tester.tap(find.text('Biologie'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Biologie');
    // A new one is simply typed.
    await tester.enterText(find.byType(TextFormField), 'Neu');
    expect(controller.text, 'Neu');
  });

  testWidgets('a slide gets a category in its editor', (tester) async {
    InfoSlide? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saved = await showDialog<InfoSlide>(
                context: context,
                builder: (_) => SlideEditorDialog(
                  quiz: quiz,
                  slide: const InfoSlide(id: 's', title: 'Geschichte'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geschichte').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-slide')));
    await tester.pumpAndSettle();
    expect(saved?.category, 'Geschichte');
  });
}
