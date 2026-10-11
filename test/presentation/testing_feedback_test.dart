import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';
import 'package:quizmo/presentation/quizmaster/editor/new_question_fields.dart';

void main() {
  testWidgets(
    'short answer editor leaves space between solution and tolerance',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewQuestionFields(
                question: const ShortAnswerQuestion(
                  id: 'q',
                  prompt: 'Question',
                  acceptedAnswers: ['Answer'],
                ),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final fields = find.byType(TextFormField);
      final solution = tester.getRect(fields.first);
      final tolerance = tester.getRect(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(tolerance.top - solution.bottom, greaterThanOrEqualTo(20));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Daily Double accepts only a positive wager within its cap on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int? wager;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: DailyDoubleWagerView(
                maxWager: 200,
                onWager: (value) => wager = value,
              ),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      final button = find.byType(FilledButton);
      for (final invalid in ['0', '-1', '201', '1.5', '']) {
        await tester.enterText(field, invalid);
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
      }
      await tester.enterText(field, '125');
      await tester.pump();
      await tester.tap(button);
      expect(wager, 125);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden media details do not render the caption', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuestionMediaView(
            media: [
              CodeAttachment(
                code: 'print(1);',
                caption: 'spoiler-filename.dart',
                hideDetails: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('spoiler-filename.dart'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('host can reorder the next team rotation', (tester) async {
    List<String>? order;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => order = await showJeopardyOrderDialog(
              context,
              const GameState(
                mode: TeamMode(),
                teams: {
                  'red': Team(id: 'red', name: 'Red'),
                  'blue': Team(id: 'blue', name: 'Blue'),
                },
              ),
            ),
            child: const Text('Edit order'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nach unten').first);
    await tester.pump();
    expect(find.text('1. Blue'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(order, ['blue', 'red']);
  });
}
