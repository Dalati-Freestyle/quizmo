/// Domain model of the Jeopardy quiz format.
///
/// A Jeopardy quiz is a *board*: every column is a category, every row is a
/// point level. Each cell merely **references** a [Question] of the quiz by id,
/// so any question kind (and every kind added in the future, including ones
/// with media attachments) can sit on the board without this file knowing it.
/// The point value is a property of the row, not of the question.
library;

import 'package:equatable/equatable.dart';

import 'json.dart';

const Object _unset = Object();

/// One field of the board.
final class JeopardyCell extends Equatable {
  /// Creates a cell pointing at [questionId].
  const JeopardyCell({this.questionId, this.isDailyDouble = false});

  /// Restores a cell from [json].
  factory JeopardyCell.fromJson(JsonMap json) => JeopardyCell(
    questionId: json.readStringOrNull('questionId'),
    isDailyDouble: json.readBool('dailyDouble'),
  );

  /// A cell without a question; it is rendered blank and cannot be picked.
  static const JeopardyCell empty = JeopardyCell();

  /// Id of the referenced `Question`, or `null` for an empty cell.
  final String? questionId;

  /// Whether picking this cell triggers a wager instead of the row points.
  final bool isDailyDouble;

  /// Whether the cell has no question.
  bool get isEmpty => questionId == null;

  /// Returns a copy with the given fields replaced.
  JeopardyCell copyWith({Object? questionId = _unset, bool? isDailyDouble}) =>
      JeopardyCell(
        questionId: identical(questionId, _unset)
            ? this.questionId
            : questionId as String?,
        isDailyDouble: isDailyDouble ?? this.isDailyDouble,
      );

  /// Serializes the cell.
  JsonMap toJson() => {'questionId': questionId, 'dailyDouble': isDailyDouble};

  @override
  List<Object?> get props => [questionId, isDailyDouble];
}

/// One column of the board.
final class JeopardyCategory extends Equatable {
  /// Creates a category named [name] holding one [cells] entry per row.
  const JeopardyCategory({required this.name, this.cells = const []});

  /// Restores a category from [json].
  factory JeopardyCategory.fromJson(JsonMap json) => JeopardyCategory(
    name: json.readString('name'),
    cells: json.readList('cells', JeopardyCell.fromJson),
  );

  /// Header shown above the column.
  final String name;

  /// Cells from the lowest to the highest point level.
  ///
  /// May be shorter than the number of rows; missing cells count as empty, so
  /// categories can hold different numbers of questions.
  final List<JeopardyCell> cells;

  /// Returns the cell in [row], or [JeopardyCell.empty] when there is none.
  JeopardyCell cellAt(int row) =>
      row >= 0 && row < cells.length ? cells[row] : JeopardyCell.empty;

  /// Returns a copy with the given fields replaced.
  JeopardyCategory copyWith({String? name, List<JeopardyCell>? cells}) =>
      JeopardyCategory(name: name ?? this.name, cells: cells ?? this.cells);

  /// Serializes the category.
  JsonMap toJson() => {
    'name': name,
    'cells': cells.map((cell) => cell.toJson()).toList(growable: false),
  };

  @override
  List<Object?> get props => [name, cells];
}

/// The static layout and rules of a Jeopardy quiz.
final class JeopardyBoard extends Equatable {
  /// Creates a board.
  const JeopardyBoard({
    required this.categories,
    required this.rowPoints,
    this.penalizeWrongAnswers = false,
    this.allowSteal = true,
  });

  /// Creates an empty board of [categoryCount] × [rowCount] cells whose row
  /// values grow by [pointStep].
  factory JeopardyBoard.blank({
    int categoryCount = 5,
    int rowCount = 5,
    int pointStep = 100,
  }) => JeopardyBoard(
    categories: [
      for (var index = 0; index < categoryCount; index++)
        JeopardyCategory(
          name: 'Category ${index + 1}',
          cells: List.filled(rowCount, JeopardyCell.empty),
        ),
    ],
    rowPoints: [for (var row = 1; row <= rowCount; row++) row * pointStep],
  );

  /// Restores a board from [json].
  factory JeopardyBoard.fromJson(JsonMap json) => JeopardyBoard(
    categories: json.readList('categories', JeopardyCategory.fromJson),
    rowPoints: json.readIntList('rowPoints'),
    penalizeWrongAnswers: json.readBool('penalizeWrongAnswers'),
    allowSteal: json.readBool('allowSteal', orElse: true),
  );

  /// Columns, left to right.
  final List<JeopardyCategory> categories;

  /// Points of every row, from the top (cheapest) down.
  ///
  /// The length of this list is the number of rows.
  final List<int> rowPoints;

  /// Whether a wrong answer costs the points of the question.
  ///
  /// A Daily Double always risks the wager, regardless of this flag.
  final bool penalizeWrongAnswers;

  /// Whether the other teams may answer after the picking team missed.
  final bool allowSteal;

  /// Number of point levels.
  int get rowCount => rowPoints.length;

  /// Highest value on the board.
  int get highestRowPoints =>
      rowPoints.isEmpty ? 0 : rowPoints.reduce((a, b) => a > b ? a : b);

  /// Returns the cell at [category]/[row], or [JeopardyCell.empty].
  JeopardyCell cellAt(int category, int row) =>
      category >= 0 && category < categories.length
      ? categories[category].cellAt(row)
      : JeopardyCell.empty;

  /// Ids of every question that sits on the board, in reading order.
  Iterable<String> get questionIds sync* {
    for (final category in categories) {
      for (final cell in category.cells) {
        if (cell.questionId case final id?) yield id;
      }
    }
  }

  /// Finds the position of [questionId], or `null` when it is not on the board.
  ({int category, int row})? locate(String questionId) {
    for (var c = 0; c < categories.length; c++) {
      final cells = categories[c].cells;
      for (var r = 0; r < cells.length; r++) {
        if (cells[r].questionId == questionId) return (category: c, row: r);
      }
    }
    return null;
  }

  /// Points of the row that holds [questionId].
  int? pointsFor(String questionId) {
    final position = locate(questionId);
    if (position == null || position.row >= rowPoints.length) return null;
    return rowPoints[position.row];
  }

  /// Name of the category that holds [questionId].
  String? categoryNameOf(String questionId) {
    final position = locate(questionId);
    return position == null ? null : categories[position.category].name;
  }

  /// Whether [questionId] sits on a Daily Double cell.
  bool isDailyDouble(String questionId) {
    final position = locate(questionId);
    return position != null &&
        categories[position.category].cellAt(position.row).isDailyDouble;
  }

  /// Returns a copy that does not reveal where the Daily Doubles are.
  JeopardyBoard redacted() => copyWith(
    categories: [
      for (final category in categories)
        category.copyWith(
          cells: [
            for (final cell in category.cells)
              cell.copyWith(isDailyDouble: false),
          ],
        ),
    ],
  );

  /// Reports every structural problem that prevents a safe save or import.
  List<String> validationErrors() {
    final errors = <String>[];
    if (categories.isEmpty) {
      errors.add('The Jeopardy board needs at least one category.');
    }
    if (rowPoints.isEmpty) {
      errors.add('The Jeopardy board needs at least one row.');
    }
    for (var row = 0; row < rowPoints.length; row++) {
      if (rowPoints[row] <= 0) {
        errors.add('Row ${row + 1} needs a positive point value.');
      }
    }

    final seen = <String>{};
    for (var c = 0; c < categories.length; c++) {
      final category = categories[c];
      if (category.name.trim().isEmpty) {
        errors.add('Category ${c + 1} needs a name.');
      }
      if (category.cells.length > rowPoints.length) {
        errors.add(
          'Category "${category.name}" has more cells than the board has rows.',
        );
      }
      for (final cell in category.cells) {
        final id = cell.questionId;
        if (id == null) {
          if (cell.isDailyDouble) {
            errors.add(
              'A Daily Double in category "${category.name}" needs a question.',
            );
          }
        } else if (!seen.add(id)) {
          errors.add('Question "$id" sits on the board more than once.');
        }
      }
    }
    return errors;
  }

  /// Returns a copy with the given fields replaced.
  JeopardyBoard copyWith({
    List<JeopardyCategory>? categories,
    List<int>? rowPoints,
    bool? penalizeWrongAnswers,
    bool? allowSteal,
  }) => JeopardyBoard(
    categories: categories ?? this.categories,
    rowPoints: rowPoints ?? this.rowPoints,
    penalizeWrongAnswers: penalizeWrongAnswers ?? this.penalizeWrongAnswers,
    allowSteal: allowSteal ?? this.allowSteal,
  );

  /// Serializes the board.
  JsonMap toJson() => {
    'categories': categories
        .map((category) => category.toJson())
        .toList(growable: false),
    'rowPoints': rowPoints,
    'penalizeWrongAnswers': penalizeWrongAnswers,
    'allowSteal': allowSteal,
  };

  @override
  List<Object?> get props => [
    categories,
    rowPoints,
    penalizeWrongAnswers,
    allowSteal,
  ];
}

/// The live Jeopardy bookkeeping of a hosted session.
///
/// Which cells were played is not stored here: that is
/// `GameState.completedQuestionIds`, shared with every other quiz format.
final class JeopardyState extends Equatable {
  /// Creates a Jeopardy session state.
  const JeopardyState({
    required this.board,
    this.currentTeamId,
    this.pendingDailyDoubleId,
    this.activePoints,
    this.activeIsDailyDouble = false,
    this.isStealRound = false,
    this.turnOrder = const [],
    this.pendingPickQuestionId,
    this.pendingPickPlayerId,
  });

  /// Starts a session on [board]; the first of [teamIds] picks first.
  factory JeopardyState.start(JeopardyBoard board, Iterable<String> teamIds) =>
      JeopardyState(
        board: board,
        currentTeamId: teamIds.isEmpty ? null : teamIds.first,
      );

  /// Restores the state from [json].
  factory JeopardyState.fromJson(JsonMap json) => JeopardyState(
    board: JeopardyBoard.fromJson(json.readObject('board')),
    pendingPickQuestionId: json.readStringOrNull('pendingPickQuestionId'),
    pendingPickPlayerId: json.readStringOrNull('pendingPickPlayerId'),
    currentTeamId: json.readStringOrNull('currentTeamId'),
    pendingDailyDoubleId: json.readStringOrNull('pendingDailyDoubleId'),
    activePoints: json.readIntOrNull('activePoints'),
    activeIsDailyDouble: json.readBool('activeIsDailyDouble'),
    isStealRound: json.readBool('isStealRound'),
    turnOrder: json['turnOrder'] == null
        ? const []
        : json.readStringList('turnOrder'),
  );

  /// The layout and rules.
  final JeopardyBoard board;
  final List<String> turnOrder;
  final String? pendingPickQuestionId;
  final String? pendingPickPlayerId;

  /// The team that picks the next cell; during a question it is the team that
  /// picked it.
  final String? currentTeamId;

  /// A Daily Double cell that was picked and still waits for its wager.
  final String? pendingDailyDoubleId;

  /// Points at stake in the question on stage (row points or the wager).
  final int? activePoints;

  /// Whether the question on stage is a Daily Double.
  final bool activeIsDailyDouble;

  /// Whether the picking team already missed and the others may answer now.
  final bool isStealRound;

  /// Whether a board question is on stage.
  bool get hasActiveQuestion => activePoints != null;

  /// Whether a miss of the picking team opens the question to the others.
  bool get canSteal => board.allowSteal && !activeIsDailyDouble;

  /// Whether a player of [teamId] may answer the question on stage.
  ///
  /// The picking team answers first; after a miss only the *other* teams may.
  /// Without teams nobody is restricted.
  bool mayAnswer(String? teamId) {
    if (!hasActiveQuestion || currentTeamId == null) return true;
    return isStealRound ? teamId != currentTeamId : teamId == currentTeamId;
  }

  /// Returns a copy that is safe to hand to a player client.
  JeopardyState redacted() => copyWith(board: board.redacted());

  /// Returns a copy with the given fields replaced.
  JeopardyState copyWith({
    JeopardyBoard? board,
    Object? currentTeamId = _unset,
    Object? pendingDailyDoubleId = _unset,
    Object? activePoints = _unset,
    bool? activeIsDailyDouble,
    bool? isStealRound,
    List<String>? turnOrder,
    Object? pendingPickQuestionId = _unset,
    Object? pendingPickPlayerId = _unset,
  }) => JeopardyState(
    board: board ?? this.board,
    currentTeamId: identical(currentTeamId, _unset)
        ? this.currentTeamId
        : currentTeamId as String?,
    pendingDailyDoubleId: identical(pendingDailyDoubleId, _unset)
        ? this.pendingDailyDoubleId
        : pendingDailyDoubleId as String?,
    activePoints: identical(activePoints, _unset)
        ? this.activePoints
        : activePoints as int?,
    activeIsDailyDouble: activeIsDailyDouble ?? this.activeIsDailyDouble,
    isStealRound: isStealRound ?? this.isStealRound,
    turnOrder: turnOrder ?? this.turnOrder,
    pendingPickQuestionId: identical(pendingPickQuestionId, _unset)
        ? this.pendingPickQuestionId
        : pendingPickQuestionId as String?,
    pendingPickPlayerId: identical(pendingPickPlayerId, _unset)
        ? this.pendingPickPlayerId
        : pendingPickPlayerId as String?,
  );

  /// Serializes the state.
  JsonMap toJson() => {
    'board': board.toJson(),
    'currentTeamId': currentTeamId,
    'pendingDailyDoubleId': pendingDailyDoubleId,
    'activePoints': activePoints,
    'activeIsDailyDouble': activeIsDailyDouble,
    'isStealRound': isStealRound,
    'turnOrder': turnOrder,
    'pendingPickQuestionId': pendingPickQuestionId,
    'pendingPickPlayerId': pendingPickPlayerId,
  };

  @override
  List<Object?> get props => [
    board,
    currentTeamId,
    pendingDailyDoubleId,
    activePoints,
    activeIsDailyDouble,
    isStealRound,
    turnOrder,
    pendingPickQuestionId,
    pendingPickPlayerId,
  ];
}
