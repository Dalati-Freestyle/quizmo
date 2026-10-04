/// Unit tests for the Jeopardy board editing of the quiz editor.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_repository.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/editor/quiz_editor_cubit.dart';

void main() {
  late QuizEditorCubit cubit;

  Quiz quiz() => Quiz(
    id: 'quiz',
    name: 'Board',
    description: 'A board.',
    category: 'Demo',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  JeopardyBoard board() => switch (cubit.state.draft.format) {
    JeopardyFormat(:final board) => board,
    StandardFormat() => throw StateError('Not a Jeopardy quiz.'),
  };

  setUp(() {
    cubit = QuizEditorCubit(repository: InMemoryQuizRepository(), quiz: quiz())
      ..useJeopardyFormat();
  });

  tearDown(() => cubit.close());

  test('switching to Jeopardy creates a blank 5x5 board', () {
    expect(board().categories, hasLength(5));
    expect(board().rowPoints, [100, 200, 300, 400, 500]);
  });

  test('switching back and forth keeps the board layout', () {
    cubit.renameCategory(0, 'Space');
    cubit.useStandardFormat();
    expect(cubit.state.draft.format, const StandardFormat());

    cubit.useJeopardyFormat();
    expect(board().categories.first.name, 'Space');
  });

  test('a new row continues the point steps and pads every category', () {
    cubit.addRow();

    expect(board().rowPoints.last, 600);
    expect(board().categories.every((c) => c.cells.length == 6), isTrue);
  });

  test('saving a cell question adds it to the quiz and the board', () {
    const question = BuzzerQuestion(id: 'q1', prompt: 'Who?');
    cubit.saveCellQuestion(category: 1, row: 2, question: question);

    expect(cubit.state.draft.questions, [question]);
    expect(board().cellAt(1, 2).questionId, 'q1');
  });

  test('editing a cell again replaces the question instead of duplicating', () {
    const first = BuzzerQuestion(id: 'q1', prompt: 'Who?');
    cubit.saveCellQuestion(category: 0, row: 0, question: first);
    cubit.saveCellQuestion(
      category: 0,
      row: 0,
      question: const BuzzerQuestion(id: 'q1', prompt: 'Who really?'),
    );

    expect(cubit.state.draft.questions, hasLength(1));
    expect(cubit.state.draft.questions.single.prompt, 'Who really?');
  });

  test('clearing a cell deletes its question', () {
    cubit.saveCellQuestion(
      category: 0,
      row: 0,
      question: const BuzzerQuestion(id: 'q1', prompt: 'Who?'),
    );
    cubit.clearCell(0, 0);

    expect(cubit.state.draft.questions, isEmpty);
    expect(board().cellAt(0, 0).isEmpty, isTrue);
  });

  test('removing a category or a row deletes the questions in it', () {
    cubit.saveCellQuestion(
      category: 0,
      row: 0,
      question: const BuzzerQuestion(id: 'q1', prompt: 'One'),
    );
    cubit.saveCellQuestion(
      category: 1,
      row: 1,
      question: const BuzzerQuestion(id: 'q2', prompt: 'Two'),
    );

    cubit.removeCategory(0);
    expect(cubit.state.draft.questions.map((q) => q.id), ['q2']);

    cubit.removeRow(1);
    expect(cubit.state.draft.questions, isEmpty);
    expect(board().rowCount, 4);
  });

  test('a Daily Double can only sit on a filled cell', () {
    cubit.toggleDailyDouble(0, 0);
    expect(board().cellAt(0, 0).isDailyDouble, isFalse);

    cubit.saveCellQuestion(
      category: 0,
      row: 0,
      question: const BuzzerQuestion(id: 'q1', prompt: 'One'),
    );
    cubit.toggleDailyDouble(0, 0);
    expect(board().cellAt(0, 0).isDailyDouble, isTrue);
  });

  test('a half filled board saves, an invalid one reports the problem', () async {
    cubit.saveCellQuestion(
      category: 0,
      row: 0,
      question: const BuzzerQuestion(id: 'q1', prompt: 'One'),
    );
    expect(await cubit.save(), isNotNull);

    cubit.setRowPoints(0, -5);
    expect(await cubit.save(), isNull);
    expect(cubit.state.error, contains('positive point value'));
  });
}

