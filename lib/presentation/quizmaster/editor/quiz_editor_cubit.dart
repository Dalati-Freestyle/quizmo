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
