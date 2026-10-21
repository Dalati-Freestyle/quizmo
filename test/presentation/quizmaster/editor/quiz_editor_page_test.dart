/// Widget tests for the quiz editor flow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_page.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_library_page.dart';
import 'package:quizmo/presentation/quizmaster/editor/question_editor.dart';

void main() {
  for (final format in [const StandardFormat(), const PokerFormat()]) {
    testWidgets('${format.label} question editing uses the quiz scoring', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = InMemoryQuizRepository();
      const rule = FixedPointsRule(correctPoints: 37, wrongPoints: -9);
      final quiz = Quiz(
        id: 'quiz',
        name: 'Scoring',
        description: 'Scoring test',
        category: 'Test',
        format: format,
        teams: const [Team(id: 'team', name: 'Team')],
        questions: const [
          TrueFalseQuestion(
            id: 'question',
            prompt: 'Existing question',
            correctAnswer: true,
            scoringRule: rule,
          ),
        ],
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: QuizEditorPage(
            repository: repository,
            quiz: quiz,
            createId: () => 'new-question',
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (format is PokerFormat) {
        expect(
          find.textContaining('Payout depends on the wager'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Existing question'));
      await tester.pumpAndSettle();
      if (format is StandardFormat) {
        expect(find.text('Scoring rule'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Correct-answer points'),
          '51',
        );
      } else {
        expect(find.text('Scoring rule'), findsNothing);
        expect(find.text('Correct-answer points'), findsNothing);
      }
      await tester.enterText(
        find.byType(TextFormField).first,
        'Edited question',
      );
      await tester.tap(find.text('Save question'));
      await tester.pumpAndSettle();

      // New questions must receive the same format as existing ones.
      await tester.tap(find.byType(QuestionTemplateDropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multiple choice').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add question'));
      await tester.pumpAndSettle();
      expect(
        find.text('Scoring rule'),
        format is StandardFormat ? findsOneWidget : findsNothing,
      );
      await tester.enterText(find.byType(TextFormField).first, 'New question');
      await tester.tap(find.text('Save question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save quiz'));
      await tester.pumpAndSettle();
      final saved = (await repository.loadAll()).single;
      expect(saved.questions, hasLength(2));
      expect(
        saved.questions.first.scoringRule,
        format is StandardFormat
            ? const FixedPointsRule(correctPoints: 51, wrongPoints: -9)
            : rule,
      );
      expect(tester.takeException(), isNull);
    });
  }

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
    final questionType = find.byType(QuestionTemplateDropdown);
    await tester.ensureVisible(questionType);
    await tester.tap(questionType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multiple choice').last);
    await tester.pumpAndSettle();
    final addQuestion = find.text('Add question');
    await tester.ensureVisible(addQuestion);
    await tester.tap(addQuestion);
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
