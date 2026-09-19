/// Unsupported-platform implementation of the quiz library factory.
library;

import '../../../core/data/quiz_repository.dart';

/// Creates no repository because this platform has no supported local store.
QuizRepository createQuizRepository() => throw const QuizRepositoryException(
  'The local quiz library is unavailable on this platform.',
);
