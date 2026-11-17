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
    StandardFormat() ||
    PokerFormat() ||
    SnowflakeFormat() => throw StateError('Not a Jeopardy quiz.'),
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

  test(
    'a half filled board saves, an invalid one reports the problem',
    () async {
      cubit.saveCellQuestion(
        category: 0,
        row: 0,
        question: const BuzzerQuestion(id: 'q1', prompt: 'One'),
      );
      expect(await cubit.save(), isNotNull);

      cubit.setRowPoints(0, -5);
      expect(await cubit.save(), isNull);
      expect(cubit.state.error, contains('positive point value'));
    },
  );

  group('moving cells', () {
    const one = BuzzerQuestion(id: 'q1', prompt: 'One');
    const three = BuzzerQuestion(id: 'q3', prompt: 'Three');

    setUp(() {
      // Category 1 / 100 points and category 1 / 300 points.
      cubit.saveCellQuestion(category: 0, row: 0, question: one);
      cubit.saveCellQuestion(category: 0, row: 2, question: three);
      cubit.toggleDailyDouble(0, 0);
    });

    test('swaps two questions within a category', () {
      cubit.moveCell(fromCategory: 0, fromRow: 0, toCategory: 0, toRow: 2);

      expect(board().cellAt(0, 0).questionId, 'q3');
      expect(board().cellAt(0, 2).questionId, 'q1');
      expect(board().pointsFor('q1'), 300);
      expect(board().pointsFor('q3'), 100);
    });

    test('the Daily Double travels with its question', () {
      cubit.moveCell(fromCategory: 0, fromRow: 0, toCategory: 0, toRow: 2);

      expect(board().cellAt(0, 0).isDailyDouble, isFalse);
      expect(board().isDailyDouble('q1'), isTrue);
    });

    test('swaps questions across categories', () {
      cubit.saveCellQuestion(
        category: 2,
        row: 3,
        question: const BuzzerQuestion(id: 'q4', prompt: 'Four'),
      );
      cubit.moveCell(fromCategory: 0, fromRow: 0, toCategory: 2, toRow: 3);

      expect(board().cellAt(0, 0).questionId, 'q4');
      expect(board().cellAt(2, 3).questionId, 'q1');
      expect(board().categoryNameOf('q1'), 'Category 3');
      expect(board().pointsFor('q1'), 400);
    });

    test('dropping on an empty cell moves the question there', () {
      cubit.moveCell(fromCategory: 0, fromRow: 2, toCategory: 4, toRow: 4);

      expect(board().cellAt(0, 2).isEmpty, isTrue);
      expect(board().cellAt(4, 4).questionId, 'q3');
      expect(board().pointsFor('q3'), 500);
    });

    test('keeps the questions of the quiz untouched', () {
      final before = cubit.state.draft.questions;
      cubit.moveCell(fromCategory: 0, fromRow: 0, toCategory: 3, toRow: 1);

      expect(cubit.state.draft.questions, before);
      expect(cubit.state.draft.validationErrors(), isEmpty);
    });

    test('dragging an empty cell or onto itself changes nothing', () {
      final before = cubit.state;
      cubit.moveCell(fromCategory: 1, fromRow: 1, toCategory: 0, toRow: 0);
      cubit.moveCell(fromCategory: 0, fromRow: 0, toCategory: 0, toRow: 0);

      expect(cubit.state, same(before));
    });
  });
}
