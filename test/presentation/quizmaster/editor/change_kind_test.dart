import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/question_editor.dart';

void main() {
  Future<Future<Question?> Function()> open(
    WidgetTester tester,
    Question question, {
    QuizFormat format = const StandardFormat(),
  }) async {
    Question? saved;
    var done = false;
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<Question>(
                MaterialPageRoute(
                  builder: (_) =>
                      QuestionEditorPage(question: question, format: format),
                ),
              );
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    return () async => done ? saved : null;
  }

  Future<void> pick(WidgetTester tester, String kind) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(QuestionTemplateDropdown));
    await tester.tap(find.byType(QuestionTemplateDropdown));
    await tester.pumpAndSettle();
    // The menu opens at the current kind and builds its entries lazily:
    // look above, then below.
    for (
      var i = 0;
      i < 24 && find.text(kind).hitTestable().evaluate().isEmpty;
      i++
    ) {
      await tester.drag(
        find.byType(Scrollable).last,
        Offset(0, i < 12 ? 48 : -48),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(kind).hitTestable().last);
    await tester.pumpAndSettle();
  }

  const choice = MultipleChoiceQuestion(
    id: 'q1',
    prompt: 'Hauptstadt?',
    options: [
      AnswerOption(id: 'a', label: 'Berlin'),
      AnswerOption(id: 'b', label: 'Bonn'),
    ],
    correctOptionId: 'a',
    scoringRule: FixedPointsRule(),
    timeLimit: Duration.zero,
  );

  testWidgets('asks before something gets lost; cancel changes nothing', (
    tester,
  ) async {
    final result = await open(tester, choice);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Unsaved input is taken along.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('prompt-field')),
        matching: find.byType(TextFormField),
      ),
      'Neue Frage?',
    );
    await pick(tester, 'Freitext');
    expect(find.byKey(const ValueKey('kind-change-dialog')), findsOneWidget);
    expect(find.text('• 1 falsche Antwortmöglichkeiten: Bonn'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Multiple choice'), findsWidgets);
    expect(find.text('Neue Frage?'), findsOneWidget);

    await pick(tester, 'Freitext');
    await tester.tap(find.byKey(const ValueKey('confirm-kind-change')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Frage?'), findsOneWidget);
    expect(find.text('Berlin'), findsOneWidget, reason: 'accepted answer');

    // Back to multiple choice: the old options are there again.
    await pick(tester, 'Multiple choice');
    if (find
        .byKey(const ValueKey('confirm-kind-change'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-kind-change')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Bonn'), findsOneWidget);
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();
    final saved = await result();
    expect(saved, isA<MultipleChoiceQuestion>());
    expect(saved!.id, 'q1');
    expect(saved.prompt, 'Neue Frage?');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incomplete question cannot be saved; leaving keeps it', (
    tester,
  ) async {
    final result = await open(tester, choice);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await pick(tester, 'Wahr / Falsch');
    await tester.tap(find.byKey(const ValueKey('confirm-kind-change')));
    await tester.pumpAndSettle();
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byKey(const ValueKey('true-false-solution')),
    );
    expect(segmented.selected, isEmpty, reason: 'nothing is guessed');
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionEditorPage), findsOneWidget);
    // Leaving without saving returns nothing: the question stays as it was.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });

  testWidgets('without loss there is no dialog', (tester) async {
    final result = await open(
      tester,
      const ShortAnswerQuestion(
        id: 'q1',
        prompt: 'P',
        acceptedAnswers: ['Antwort'],
        timeLimit: Duration.zero,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await pick(tester, 'Fast buzzer');
    expect(find.byKey(const ValueKey('kind-change-dialog')), findsNothing);
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();
    final saved = await result();
    expect(saved, isA<BuzzerQuestion>());
    expect((saved! as BuzzerQuestion).expectedAnswer, 'Antwort');
  });

  testWidgets('snowflake only offers kinds it can compare', (tester) async {
    await open(
      tester,
      const TrueFalseQuestion(id: 'q1', prompt: 'P', timeLimit: Duration.zero),
      format: const SnowflakeFormat(),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(QuestionTemplateDropdown));
    await tester.pumpAndSettle();
    expect(find.text('Freitext'), findsNothing);
    expect(find.text('Ort auf der Karte'), findsNothing);
  });
}
