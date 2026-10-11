import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/player/questions/new_question_views.dart';

void main() {
  testWidgets('matching allows replacing a complete assignment', (
    tester,
  ) async {
    Map<String, String>? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchingQuestionView(
            question: const MatchingQuestion(
              id: 'q',
              prompt: '?',
              leftItems: [
                AnswerOption(id: 'a', label: 'A'),
                AnswerOption(id: 'b', label: 'B'),
              ],
              rightItems: [
                AnswerOption(id: 'x', label: 'X'),
                AnswerOption(id: 'y', label: 'Y'),
              ],
            ),
            enabled: true,
            onSubmit: (v) => answer = v,
          ),
        ),
      ),
    );
    Future<void> choose(int index, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose(0, 'X');
    final remaining = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).at(1),
    ).items!;
    expect(remaining.map((item) => item.value), ['y', 'x']);
    expect(remaining.last.enabled, isFalse);
    await choose(1, 'Y');
    await choose(1, 'Auswahl löschen');
    await choose(0, 'Y');
    await choose(1, 'X');
    await tester.tap(find.text('Zuordnung senden'));
    expect(answer, {'a': 'y', 'b': 'x'});
  });
  testWidgets('short answer submits trimmed text', (tester) async {
    String? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortAnswerQuestionView(
            question: const ShortAnswerQuestion(id: 'q', prompt: '?'),
            enabled: true,
            onSubmit: (v) => answer = v,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), ' Berlin ');
    await tester.pump();
    await tester.tap(find.text('Antwort senden'));
    expect(answer, 'Berlin');
  });
  testWidgets('ordering buttons change the submitted permutation', (
    tester,
  ) async {
    List<String>? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderingQuestionView(
            question: const OrderingQuestion(
              id: 'q',
              prompt: '?',
              items: [
                AnswerOption(id: 'a', label: 'A'),
                AnswerOption(id: 'b', label: 'B'),
              ],
            ),
            enabled: true,
            onSubmit: (v) => answer = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reihenfolge senden'));
    final initial = [...answer!];
    await tester.tap(find.byIcon(Icons.arrow_downward).first);
    await tester.pump();
    await tester.tap(find.text('Reihenfolge senden'));
    expect(answer, initial.reversed.toList());
  });
  testWidgets('estimation rejects NaN and supports decimal comma', (
    tester,
  ) async {
    double? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimationQuestionView(
            question: const EstimationQuestion(id: 'q', prompt: '?'),
            enabled: true,
            onSubmit: (v) => answer = v,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.pump();
    await tester.tap(find.text('Schätzung senden'));
    expect(answer, isNull);
    await tester.enterText(find.byType(TextField), '12,5');
    await tester.pump();
    await tester.tap(find.text('Schätzung senden'));
    expect(answer, 12.5);
  });
}
