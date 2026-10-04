/// State management for editing one quiz definition.
library;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/data/quiz_repository.dart';
import '../../../core/models/models.dart';

/// Snapshot of the quiz editor.
final class QuizEditorState extends Equatable {
  /// Creates an editor state for [draft].
  const QuizEditorState({
    required this.draft,
    this.isSaving = false,
    this.error,
  });

  /// Mutable-by-replacement quiz definition shown in the editor.
  final Quiz draft;

  /// Whether the draft is currently being written to the repository.
  final bool isSaving;

  /// Most recent validation or persistence error.
  final String? error;

  /// Returns a copy with selected fields replaced.
  QuizEditorState copyWith({
    Quiz? draft,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) => QuizEditorState(
    draft: draft ?? this.draft,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [draft, isSaving, error];
}

/// Edits and saves a quiz without exposing persistence to widgets.
final class QuizEditorCubit extends Cubit<QuizEditorState> {
  /// Creates an editor for [quiz] backed by [repository].
  QuizEditorCubit({
    required QuizRepository repository,
    required Quiz quiz,
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now,
       super(QuizEditorState(draft: quiz));

  final QuizRepository _repository;
  final DateTime Function() _now;

  /// Replaces the general metadata while retaining questions and teams.
  void updateMetadata({
    required String name,
    required String description,
    required String category,
  }) => _replaceDraft(
    state.draft.copyWith(
      name: name,
      description: description,
      category: category,
    ),
  );

  /// Adds [team] to the end of the team list.
  void addTeam(Team team) =>
      _replaceDraft(state.draft.copyWith(teams: [...state.draft.teams, team]));

  /// Replaces [team] by matching its ID.
  void updateTeam(Team team) => _replaceDraft(
    state.draft.copyWith(
      teams: [
        for (final existing in state.draft.teams)
          if (existing.id == team.id) team else existing,
      ],
    ),
  );

  /// Removes the team identified by [teamId].
  void removeTeam(String teamId) => _replaceDraft(
    state.draft.copyWith(
      teams: state.draft.teams
          .where((team) => team.id != teamId)
          .toList(growable: false),
    ),
  );

  /// Adds [question] to the end of the question bank.
  void addQuestion(Question question) => _replaceDraft(
    state.draft.copyWith(questions: [...state.draft.questions, question]),
  );

  /// Replaces [question] by matching its ID.
  void updateQuestion(Question question) => _replaceDraft(
    state.draft.copyWith(
      questions: [
        for (final existing in state.draft.questions)
          if (existing.id == question.id) question else existing,
      ],
    ),
  );

  /// Removes the question identified by [questionId].
  void removeQuestion(String questionId) => _replaceDraft(
    state.draft.copyWith(
      questions: state.draft.questions
          .where((question) => question.id != questionId)
          .toList(growable: false),
    ),
  );

  /// Moves a question from [oldIndex] to [newIndex].
  void reorderQuestions(int oldIndex, int newIndex) {
    final questions = [...state.draft.questions];
    final question = questions.removeAt(oldIndex);
    questions.insert(newIndex, question);
    _replaceDraft(state.draft.copyWith(questions: questions));
  }

  // ---------------------------------------------------------------- format ---

  /// Plays the quiz as a plain list of questions.
  ///
  /// The questions stay; the board layout is remembered in case the host
  /// switches back to Jeopardy.
  void useStandardFormat() {
    if (_board case final board?) _stashedBoard = board;
    _replaceDraft(state.draft.copyWith(format: const StandardFormat()));
  }

  /// Plays the quiz as a Jeopardy board.
  ///
  /// Reuses the previous board of this editing session or starts a blank
  /// 5 × 5 one.
  void useJeopardyFormat() {
    if (_board != null) return;
    final board = _stashedBoard ?? JeopardyBoard.blank();
    _replaceDraft(state.draft.copyWith(format: JeopardyFormat(board)));
  }

  void usePokerFormat({int startingChips = 100}) {
    if (_board case final board?) _stashedBoard = board;
    _replaceDraft(
      state.draft.copyWith(format: PokerFormat(startingChips: startingChips)),
    );
  }

  /// Switches the two board rules.
  void updateBoardRules({bool? penalizeWrongAnswers, bool? allowSteal}) =>
      _updateBoard(
        (board) => board.copyWith(
          penalizeWrongAnswers: penalizeWrongAnswers,
          allowSteal: allowSteal,
        ),
      );

  /// Appends an empty category.
  void addCategory() => _updateBoard(
    (board) => board.copyWith(
      categories: [
        ...board.categories,
        JeopardyCategory(
          name: 'Category ${board.categories.length + 1}',
          cells: _emptyCells(board.rowCount),
        ),
      ],
    ),
  );

  /// Renames the category in column [index].
  void renameCategory(int index, String name) => _updateBoard(
    (board) => board.copyWith(
      categories: [
        for (var i = 0; i < board.categories.length; i++)
          if (i == index)
            board.categories[i].copyWith(name: name)
          else
            board.categories[i],
      ],
    ),
  );

  /// Removes the category in column [index] together with its questions.
  void removeCategory(int index) => _updateBoard((board) {
    if (board.categories.length <= 1) return board;
    return board.copyWith(categories: [...board.categories]..removeAt(index));
  }, dropQuestionsOf: (board) => [...board.categories[index].cells]);

  /// Appends a row worth one more step than the current last row.
  void addRow() => _updateBoard((board) {
    final points = board.rowPoints;
    final last = points.isEmpty ? 0 : points.last;
    final step = points.length >= 2 ? last - points[points.length - 2] : 100;
    final nextPoints = last + (step > 0 ? step : 100);
    return board.copyWith(
      rowPoints: [...points, nextPoints],
      categories: [
        for (final category in board.categories)
          category.copyWith(
            cells: [
              ..._padded(category.cells, board.rowCount),
              JeopardyCell.empty,
            ],
          ),
      ],
    );
  });

  /// Sets the points of the row at [row].
  void setRowPoints(int row, int points) => _updateBoard(
    (board) => board.copyWith(
      rowPoints: [
        for (var i = 0; i < board.rowPoints.length; i++)
          if (i == row) points else board.rowPoints[i],
      ],
    ),
  );

  /// Removes the row at [row] together with its questions.
  void removeRow(int row) => _updateBoard(
    (board) {
      if (board.rowCount <= 1) return board;
      return board.copyWith(
        rowPoints: [...board.rowPoints]..removeAt(row),
        categories: [
          for (final category in board.categories)
            category.copyWith(
              cells: [
                for (var i = 0; i < category.cells.length; i++)
                  if (i != row) category.cells[i],
              ],
            ),
        ],
      );
    },
    dropQuestionsOf: (board) => [
      for (final category in board.categories) category.cellAt(row),
    ],
  );

  /// Stores [question] in the cell at [category]/[row].
  ///
  /// A new question is appended to the quiz; an existing one is replaced.
  void saveCellQuestion({
    required int category,
    required int row,
    required Question question,
  }) {
    final board = _board;
    if (board == null) return;
    final known = state.draft.questions.any((q) => q.id == question.id);
    final questions = known
        ? [
            for (final existing in state.draft.questions)
              if (existing.id == question.id) question else existing,
          ]
        : [...state.draft.questions, question];
    final updated = board.copyWith(
      categories: [
        for (var c = 0; c < board.categories.length; c++)
          if (c == category)
            board.categories[c].copyWith(
              cells: [
                for (final (index, cell) in _padded(
                  board.categories[c].cells,
                  board.rowCount,
                ).indexed)
                  if (index == row)
                    cell.copyWith(questionId: question.id)
                  else
                    cell,
              ],
            )
          else
            board.categories[c],
      ],
    );
    _replaceDraft(
      state.draft.copyWith(
        questions: questions,
        format: JeopardyFormat(updated),
      ),
    );
  }

  /// Flips the Daily Double flag of the cell at [category]/[row].
  void toggleDailyDouble(int category, int row) => _updateBoard(
    (board) => _replaceCell(
      board,
      category,
      row,
      (cell) => cell.isEmpty
          ? cell
          : cell.copyWith(isDailyDouble: !cell.isDailyDouble),
    ),
  );

  /// Empties the cell at [category]/[row] and deletes its question.
  void clearCell(int category, int row) => _updateBoard(
    (board) => _replaceCell(board, category, row, (_) => JeopardyCell.empty),
    dropQuestionsOf: (board) => [board.cellAt(category, row)],
  );

  JeopardyBoard? get _board => switch (state.draft.format) {
    JeopardyFormat(:final board) => board,
    StandardFormat() || PokerFormat() => null,
  };

  JeopardyBoard? _stashedBoard;

  /// Applies [update] to the board; questions of the cells returned by
  /// [dropQuestionsOf] (evaluated on the old board) leave the quiz.
  void _updateBoard(
    JeopardyBoard Function(JeopardyBoard board) update, {
    List<JeopardyCell> Function(JeopardyBoard board)? dropQuestionsOf,
  }) {
    final board = _board;
    if (board == null) return;
    final updated = update(board);
    if (identical(updated, board)) return;
    final dropped = {
      for (final cell in dropQuestionsOf?.call(board) ?? const <JeopardyCell>[])
        ?cell.questionId,
    };
    _replaceDraft(
      state.draft.copyWith(
        questions: [
          for (final question in state.draft.questions)
            if (!dropped.contains(question.id)) question,
        ],
        format: JeopardyFormat(updated),
      ),
    );
  }

  static JeopardyBoard _replaceCell(
    JeopardyBoard board,
    int category,
    int row,
    JeopardyCell Function(JeopardyCell cell) transform,
  ) => board.copyWith(
    categories: [
      for (var c = 0; c < board.categories.length; c++)
        if (c == category)
          board.categories[c].copyWith(
            cells: [
              for (final (index, cell) in _padded(
                board.categories[c].cells,
                board.rowCount,
              ).indexed)
                if (index == row) transform(cell) else cell,
            ],
          )
        else
          board.categories[c],
    ],
  );

  static List<JeopardyCell> _emptyCells(int count) =>
      List.filled(count, JeopardyCell.empty);

  static List<JeopardyCell> _padded(List<JeopardyCell> cells, int length) => [
    ...cells,
    for (var i = cells.length; i < length; i++) JeopardyCell.empty,
  ];

  /// Validates and stores the current draft, returning the saved quiz on success.
  Future<Quiz?> save() async {
    emit(state.copyWith(isSaving: true, clearError: true));
    final savedQuiz = state.draft.copyWith(updatedAt: _now().toUtc());
    try {
      savedQuiz.validate();
      await _repository.save(savedQuiz);
      emit(QuizEditorState(draft: savedQuiz));
      return savedQuiz;
    } on Object catch (error) {
      emit(state.copyWith(isSaving: false, error: _errorMessage(error)));
      return null;
    }
  }

  void _replaceDraft(Quiz draft) =>
      emit(state.copyWith(draft: draft, clearError: true));

  static String _errorMessage(Object error) => switch (error) {
    QuizValidationException(:final messages) => messages.join(' '),
    QuizRepositoryException(:final message) => message,
    _ => 'Could not save this quiz: $error',
  };
}
