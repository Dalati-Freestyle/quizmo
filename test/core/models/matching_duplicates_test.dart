/// Matching questions with the same value on the right more than once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/editor/new_question_fields.dart';

const dishes = MatchingQuestion(
  id: 'm',
  prompt: 'Which meat?',
  leftItems: [
    AnswerOption(id: 'kassler', label: 'Kassler'),
    AnswerOption(id: 'haxe', label: 'Haxe'),
    AnswerOption(id: 'tafelspitz', label: 'Tafelspitz'),
  ],
  rightItems: [
    AnswerOption(id: 'p1', label: 'Schwein'),
    AnswerOption(id: 'r', label: 'Rind'),
    AnswerOption(id: 'p2', label: 'schwein '),
  ],
  correctPairs: {'kassler': 'p1', 'haxe': 'p2', 'tafelspitz': 'r'},
);

MatchingAnswer pairs(Map<String, String> value) => MatchingAnswer(
  playerId: 'p',
  questionId: 'm',
  clientTimestampMicros: 1,
  clockOffsetMicros: 0,
  pairs: value,
);

void main() {
  final stored = pairs(dishes.correctPairs!);
  final swapped = pairs({'kassler': 'p2', 'haxe': 'p1', 'tafelspitz': 'r'});
  final wrong = pairs({'kassler': 'r', 'haxe': 'p1', 'tafelspitz': 'p2'});

  test('equal values on the right are interchangeable', () {
    expect(dishes.structureErrors, isEmpty);
    expect(dishes.solutionErrors, isEmpty);
    expect(dishes.accuracy(stored), 1);
    expect(dishes.accuracy(swapped), 1);
    expect(dishes.accuracy(wrong), 0);
  });

  test('swapping equal values is the same answer for Biggest Snowflake', () {
    expect(dishes.uniquenessKey(stored), dishes.uniquenessKey(swapped));
    expect(dishes.uniquenessKey(stored), isNot(dishes.uniquenessKey(wrong)));
  });

  testWidgets('the editor saves the same value on several lines', (
    tester,
  ) async {
    Map<String, Object?> fields = {};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SingleChildScrollView(
            child: NewQuestionFields(
              question: dishes,
              onChanged: (value) => fields = value,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Kassler = Schwein\nHaxe = Schwein\nTafelspitz = Rind',
    );
    final edited =
        Question.fromJson({...dishes.toJson(), ...fields}) as MatchingQuestion;
    expect(edited.structureErrors, isEmpty);
    expect(edited.solutionErrors, isEmpty);
    expect(edited.correctPairs!.values.toSet(), hasLength(3));
    expect(edited.solutionLabel, contains('Haxe → Schwein'));
    expect(edited.solutionLabel, contains('Kassler → Schwein'));
    expect(edited.solutionLabel, contains('Tafelspitz → Rind'));
  });
}
