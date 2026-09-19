/// State management for the local quiz library.
library;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/data/quiz_import_export.dart';
import '../../../core/data/quiz_repository.dart';
import '../../../core/data/sample_quiz.dart';
import '../../../core/models/models.dart';

/// Snapshot of the quiz library screen.
final class QuizLibraryState extends Equatable {
  /// Creates a library state.
  const QuizLibraryState({
    this.quizzes = const [],
    this.isLoading = true,
    this.isBusy = false,
    this.error,
  });

  /// Current quizzes available for editing or hosting.
  final List<Quiz> quizzes;

  /// Whether the initial library read is still in progress.
  final bool isLoading;

  /// Whether an import or delete operation is in progress.
  final bool isBusy;

  /// Most recent recoverable operation error.
  final String? error;

  /// Returns a copy with selected fields replaced.
  QuizLibraryState copyWith({
    List<Quiz>? quizzes,
    bool? isLoading,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) => QuizLibraryState(
    quizzes: quizzes ?? this.quizzes,
    isLoading: isLoading ?? this.isLoading,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [quizzes, isLoading, isBusy, error];
}

/// Loads, seeds, imports, and deletes local quizzes.
final class QuizLibraryCubit extends Cubit<QuizLibraryState> {
  /// Creates a controller backed by [repository].
  QuizLibraryCubit({
    required QuizRepository repository,
    String Function()? createId,
    DateTime Function()? now,
  }) : _repository = repository,
       _createId = createId ?? _newId,
       _now = now ?? DateTime.now,
       super(const QuizLibraryState());

  final QuizRepository _repository;
  final String Function() _createId;
  final DateTime Function() _now;

  /// Repository shared with child editor routes.
  QuizRepository get repository => _repository;

  /// Loads the library and persists the sample quiz if it is empty.
  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      var quizzes = await _repository.loadAll();
      if (quizzes.isEmpty) {
        final sample = createSampleQuiz(_now());
        await _repository.save(sample);
        quizzes = [sample];
      }
      emit(QuizLibraryState(quizzes: quizzes, isLoading: false));
    } on Object catch (error) {
      emit(
        QuizLibraryState(
          quizzes: state.quizzes,
          isLoading: false,
          error: _errorMessage(error),
        ),
      );
    }
  }

  /// Imports [contents] only after decoding and validating the complete file.
  Future<Quiz?> importContents(String contents) async {
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      final imported = await importQuiz(
        contents: contents,
        repository: _repository,
        createId: _createId,
        now: _now,
      );
      emit(
        QuizLibraryState(quizzes: await _repository.loadAll(), isBusy: false),
      );
      return imported;
    } on Object catch (error) {
      emit(state.copyWith(isBusy: false, error: _errorMessage(error)));
      return null;
    }
  }

  /// Deletes [quiz] from the library.
  Future<void> delete(Quiz quiz) async {
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      await _repository.delete(quiz.id);
      var quizzes = await _repository.loadAll();
      if (quizzes.isEmpty) {
        final sample = createSampleQuiz(_now());
        await _repository.save(sample);
        quizzes = [sample];
      }
      emit(QuizLibraryState(quizzes: quizzes, isBusy: false));
    } on Object catch (error) {
      emit(state.copyWith(isBusy: false, error: _errorMessage(error)));
    }
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static String _errorMessage(Object error) => switch (error) {
    QuizImportException(:final message) => message,
    QuizRepositoryException(:final message) => message,
    QuizValidationException(:final messages) => messages.join(' '),
    _ => 'Could not update the quiz library: $error',
  };
}
