/// Unit tests for the Jeopardy board model and its quiz integration.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

const BuzzerQuestion _q1 = BuzzerQuestion(id: 'q1', prompt: 'One');
const BuzzerQuestion _q2 = BuzzerQuestion(id: 'q2', prompt: 'Two');

Quiz _quiz(
  JeopardyBoard board, {
  List<Question> questions = const [_q1, _q2],
}) => Quiz(
  id: 'quiz',
  name: 'Board',
  description: 'A board.',
  category: 'Demo',
  questions: questions,
  format: JeopardyFormat(board),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('blank boards have the requested size and growing points', () {
    final board = JeopardyBoard.blank(
      categoryCount: 3,
      rowCount: 4,
      pointStep: 50,
    );

    expect(board.categories, hasLength(3));
    expect(board.rowPoints, [50, 100, 150, 200]);
    expect(board.categories.every((c) => c.cells.length == 4), isTrue);
  });

  test('locates questions and reads the points of their row', () {
    const board = JeopardyBoard(
      rowPoints: [10, 20],
      categories: [
        JeopardyCategory(
          name: 'A',
          cells: [
            JeopardyCell(questionId: 'q1'),
            JeopardyCell.empty,
          ],
        ),
        JeopardyCategory(
          name: 'B',
          cells: [
            JeopardyCell.empty,
            JeopardyCell(questionId: 'q2'),
          ],
        ),
      ],
    );

    expect(board.locate('q2'), (category: 1, row: 1));
    expect(board.pointsFor('q2'), 20);
    expect(board.categoryNameOf('q1'), 'A');
    expect(board.pointsFor('missing'), isNull);
  });

  test('a ragged category may hold fewer cells than there are rows', () {
    const board = JeopardyBoard(
      rowPoints: [10, 20, 30],
      categories: [
        JeopardyCategory(
          name: 'Short',
          cells: [JeopardyCell(questionId: 'q1')],
        ),
      ],
    );

    expect(board.validationErrors(), isEmpty);
    expect(board.cellAt(0, 2).isEmpty, isTrue);
  });

  test('a Jeopardy quiz survives a JSON round trip', () {
    final quiz = _quiz(
      const JeopardyBoard(
        rowPoints: [10, 20],
        penalizeWrongAnswers: true,
        allowSteal: false,
        categories: [
          JeopardyCategory(
            name: 'A',
            cells: [
              JeopardyCell(questionId: 'q1', isDailyDouble: true),
              JeopardyCell(questionId: 'q2'),
            ],
          ),
        ],
      ),
    );

    expect(Quiz.fromJson(quiz.toJson()), quiz);
  });

  test('a quiz file without a format is a standard quiz', () {
    final json = _quiz(
      JeopardyBoard.blank(),
    ).copyWith(format: const StandardFormat()).toJson()..remove('format');

    expect(Quiz.fromJson(json).format, const StandardFormat());
  });

  test('rejects a board that references an unknown question', () {
    final quiz = _quiz(
      const JeopardyBoard(
        rowPoints: [10],
        categories: [
          JeopardyCategory(
            name: 'A',
            cells: [JeopardyCell(questionId: 'nope')],
          ),
        ],
      ),
    );

    expect(quiz.validationErrors().join(' '), contains('unknown question'));
  });

  test('rejects a question that sits on the board twice', () {
    final quiz = _quiz(
      const JeopardyBoard(
        rowPoints: [10, 20],
        categories: [
          JeopardyCategory(
            name: 'A',
            cells: [
              JeopardyCell(questionId: 'q1'),
              JeopardyCell(questionId: 'q1'),
            ],
          ),
        ],
      ),
    );

    expect(quiz.validationErrors().join(' '), contains('more than once'));
  });

  test('rejects missing names and non positive points', () {
    final errors = const JeopardyBoard(
      rowPoints: [0],
      categories: [JeopardyCategory(name: ' ')],
    ).validationErrors().join(' ');

    expect(errors, contains('positive point value'));
    expect(errors, contains('needs a name'));
  });

  group('swapCells', () {
    final board = JeopardyBoard(
      categories: const [
        JeopardyCategory(
          name: 'A',
          cells: [
            JeopardyCell(questionId: 'q1', isDailyDouble: true),
            JeopardyCell(questionId: 'q2'),
          ],
        ),
        // Shorter than the board: row 1 does not exist yet.
        JeopardyCategory(name: 'B', cells: [JeopardyCell.empty]),
      ],
      rowPoints: const [100, 200],
    );

    test('swaps two cells with their Daily Double flags', () {
      final swapped = board.swapCells(
        (category: 0, row: 0),
        (category: 0, row: 1),
      );
      expect(swapped.cellAt(0, 0), const JeopardyCell(questionId: 'q2'));
      expect(
        swapped.cellAt(0, 1),
        const JeopardyCell(questionId: 'q1', isDailyDouble: true),
      );
      expect(swapped.rowPoints, board.rowPoints);
      expect(swapped.pointsFor('q1'), 200);
      expect(swapped.validationErrors(), isEmpty);
    });

    test('moves into a cell the category does not store yet', () {
      final moved = board.swapCells(
        (category: 0, row: 1),
        (category: 1, row: 1),
      );
      expect(moved.cellAt(0, 1), JeopardyCell.empty);
      expect(moved.cellAt(1, 1).questionId, 'q2');
      expect(moved.categories[1].cells, hasLength(2));
      expect(moved.validationErrors(), isEmpty);
    });

    test('the same or an out of range position leaves the board alone', () {
      expect(
        board.swapCells((category: 0, row: 0), (category: 0, row: 0)),
        same(board),
      );
      expect(
        board.swapCells((category: 0, row: 0), (category: 2, row: 0)),
        same(board),
      );
      expect(
        board.swapCells((category: 0, row: 0), (category: 1, row: 2)),
        same(board),
      );
    });

    test('the serialized form is unchanged apart from the positions', () {
      final swapped = board.swapCells(
        (category: 0, row: 0),
        (category: 1, row: 0),
      );
      expect(JeopardyBoard.fromJson(swapped.toJson()), swapped);
    });
  });
}
