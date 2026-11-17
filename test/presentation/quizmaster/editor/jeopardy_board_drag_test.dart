/// Widget tests for moving questions on the Jeopardy board by drag and drop.
library;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/jeopardy_board_editor.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_cubit.dart';

void main() {
  late QuizEditorCubit cubit;

  JeopardyBoard board() => switch (cubit.state.draft.format) {
    JeopardyFormat(:final board) => board,
    StandardFormat() ||
    PokerFormat() ||
    SnowflakeFormat() => throw StateError('Not a Jeopardy quiz.'),
  };

  Future<void> pumpBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    cubit =
        QuizEditorCubit(
            repository: InMemoryQuizRepository(),
            quiz: Quiz(
              id: 'quiz',
              name: 'Board',
              description: 'A board.',
              category: 'Demo',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          )
          ..useJeopardyFormat()
          ..saveCellQuestion(
            category: 0,
            row: 0,
            question: const BuzzerQuestion(id: 'q1', prompt: 'One'),
          )
          ..saveCellQuestion(
            category: 0,
            row: 2,
            question: const BuzzerQuestion(id: 'q3', prompt: 'Three'),
          )
          ..saveCellQuestion(
            category: 2,
            row: 3,
            question: const BuzzerQuestion(id: 'q4', prompt: 'Four'),
          );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocBuilder<QuizEditorCubit, QuizEditorState>(
              bloc: cubit,
              builder: (context, state) => JeopardyBoardEditorPanel(
                quiz: state.draft,
                board: board(),
                cubit: cubit,
                createId: () => 'new',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cellWith(String text) => find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((widget) => widget is DragTarget),
  );

  Finder handleOf(String text) => find.descendant(
    of: cellWith(text),
    matching: find.byIcon(Icons.drag_indicator),
  );

  Future<void> dragHandle(
    WidgetTester tester,
    String text,
    Offset target,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(handleOf(text)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a handle onto another question swaps them', (
    tester,
  ) async {
    await pumpBoard(tester);

    // Category 1 / 100 onto category 1 / 300.
    await dragHandle(tester, 'One', tester.getCenter(cellWith('Three')));
    expect(board().cellAt(0, 0).questionId, 'q3');
    expect(board().cellAt(0, 2).questionId, 'q1');

    // Across categories: category 1 / 300 onto category 3 / 400.
    await dragHandle(tester, 'One', tester.getCenter(cellWith('Four')));
    expect(board().cellAt(0, 2).questionId, 'q4');
    expect(board().cellAt(2, 3).questionId, 'q1');
  });

  testWidgets('dropping onto an empty cell moves the question there', (
    tester,
  ) async {
    await pumpBoard(tester);

    // The last empty cell in reading order is category 5 / 500.
    final emptyCell = tester.getCenter(find.text('Add question').last);
    await dragHandle(tester, 'Three', emptyCell);

    expect(board().cellAt(0, 2).isEmpty, isTrue);
    expect(board().cellAt(4, 4).questionId, 'q3');
    expect(cubit.state.draft.questions, hasLength(3));
  });

  testWidgets('a long press drags the whole cell on touch screens', (
    tester,
  ) async {
    await pumpBoard(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Four')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(cellWith('One')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(board().cellAt(0, 0).questionId, 'q4');
    expect(board().cellAt(2, 3).questionId, 'q1');
  });

  testWidgets('tapping a cell still opens the question editor', (tester) async {
    await pumpBoard(tester);

    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(find.text('Save question'), findsOneWidget);
  });
}
