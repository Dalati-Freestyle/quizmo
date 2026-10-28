/// The persisted definition of a reusable quiz.
library;

import 'package:equatable/equatable.dart';

import 'jeopardy.dart';
import 'json.dart';
import 'question.dart';
import 'quiz_format.dart';
import 'team.dart';

/// Describes quiz content that cannot be saved or imported safely.
final class QuizValidationException implements Exception {
  /// Creates an exception containing all detected [messages].
  const QuizValidationException(this.messages);

  /// Human-readable validation failures.
  final List<String> messages;

  @override
  String toString() => 'QuizValidationException: ${messages.join(' ')}';
}

/// A named, versioned question bank that can be edited and hosted repeatedly.
///
/// Historical schema importers convert files into the current quiz model.
final class Quiz extends Equatable {
  /// Creates a quiz definition.
  const Quiz({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.questions = const [],
    this.teams = const [],
    this.format = const StandardFormat(),
    this.schemaVersion = currentSchemaVersion,
  });

  /// The newest file format this version of Quizmo can read and write.
  static const int currentSchemaVersion = 6;

  /// Restores and validates a quiz definition from [json].
  factory Quiz.fromJson(JsonMap json) {
    final version = json['schemaVersion'];
    if (version is! num || !version.isFinite || version != version.toInt()) {
      throw const JsonContractException(
        'A quiz file must include an integer "schemaVersion".',
      );
    }
    if (version > currentSchemaVersion) {
      throw QuizSchemaUpdateRequiredException(
        requiredVersion: version.toInt(),
        supportedVersion: currentSchemaVersion,
      );
    }
    return switch (version.toInt()) {
      1 => Quiz._fromJsonV1(json),
      2 => Quiz._fromJsonV2(json),
      3 => Quiz._fromJsonV3(json),
      4 => Quiz._fromJsonV4(json),
      5 => Quiz._fromJsonV5(json),
      6 => Quiz._fromJsonV6(json),
      final unsupported => throw JsonContractException(
        'Unsupported quiz schemaVersion $unsupported. '
        'This app supports schema versions 1 through $currentSchemaVersion.',
      ),
    };
  }

  factory Quiz._fromJsonV1(JsonMap json) => Quiz._fromJsonV2(json);

  factory Quiz._fromJsonV2(JsonMap json) => Quiz._fromJsonV3(json);

  factory Quiz._fromJsonV3(JsonMap json) => Quiz._fromJsonV4(json);

  factory Quiz._fromJsonV4(JsonMap json) => Quiz._fromJsonV5(json);

  factory Quiz._fromJsonV5(JsonMap json) => Quiz._fromJsonV6({
    ...json,
    'questions': json.readList(
      'questions',
      (question) => {
        ...question,
        if (question['type'] == 'shortAnswer') 'manualGrading': false,
      },
    ),
  });

  factory Quiz._fromJsonV6(JsonMap json) {
    final quiz = Quiz(
      schemaVersion: currentSchemaVersion,
      id: json.readString('id'),
      name: json.readString('name'),
      description: json.readString('description'),
      category: json.readString('category'),
      questions: json.readList('questions', Question.fromJson),
      teams: json.readList('teams', Team.fromJson),
      // Files written before formats existed have no entry: plain quiz.
      format: switch (json.readObjectOrNull('format')) {
        final JsonMap value => QuizFormat.fromJson(value),
        null => const StandardFormat(),
      },
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        json.readInt('createdAtMicros'),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        json.readInt('updatedAtMicros'),
        isUtc: true,
      ),
    );
    quiz.validate();
    return quiz;
  }

  /// Current schema version of the in-memory quiz after migration.
  final int schemaVersion;

  /// Stable identifier used by the local library.
  final String id;

  /// Short title rendered in the quiz library.
  final String name;

  /// Longer summary shown before hosting the quiz.
  final String description;

  /// Top-level grouping label for the quiz library.
  final String category;

  /// Ordered question bank presented to the host.
  final List<Question> questions;

  /// Optional teams offered to joining players.
  final List<Team> teams;

  /// How the question bank is played; see [QuizFormat].
  final QuizFormat format;

  /// Instant at which this quiz was first created.
  final DateTime createdAt;

  /// Instant at which this quiz was last changed.
  final DateTime updatedAt;

  /// Teams keyed by their stable IDs for the quiz engine.
  Map<String, Team> get teamsById => {for (final team in teams) team.id: team};

  /// Reports every content violation that prevents a safe save or import.
  List<String> validationErrors() {
    final errors = <String>[];
    if (schemaVersion != currentSchemaVersion) {
      errors.add(
        'Unsupported quiz schemaVersion $schemaVersion. '
        'Expected $currentSchemaVersion.',
      );
    }
    if (id.trim().isEmpty) errors.add('Quiz ID must not be empty.');
    if (name.trim().isEmpty) errors.add('Quiz name must not be empty.');
    if (description.trim().isEmpty) {
      errors.add('Quiz description must not be empty.');
    }
    if (category.trim().isEmpty) errors.add('Quiz category must not be empty.');
    if (updatedAt.isBefore(createdAt)) {
      errors.add('Quiz updatedAt must not be before createdAt.');
    }
    _addDuplicateIdError(errors, teams.map((team) => team.id), 'team');
    _addDuplicateIdError(
      errors,
      questions.map((question) => question.id),
      'question',
    );

    for (final team in teams) {
      if (team.id.trim().isEmpty) errors.add('A team ID must not be empty.');
      if (team.name.trim().isEmpty) {
        errors.add('Team "${team.id}" needs a name.');
      }
    }
    final encodedMediaSize = questions.fold<int>(
      0,
      (total, q) =>
          total +
          [
            ...q.media,
            ...q.solutionMedia,
          ].fold<int>(0, (sum, m) => sum + (m.asset?.data?.length ?? 0)),
    );
    if (encodedMediaSize > 90 * 1024 * 1024) {
      errors.add(
        'Medien im Quiz dürfen zusammen maximal 90 MiB im Export belegen.',
      );
    }
    for (final question in questions) {
      errors.addAll(_questionValidationErrors(question));
    }
    switch (format) {
      case PokerFormat(:final startingChips):
        if (startingChips < 1 || startingChips > 1000000) {
          errors.add('Startchips müssen zwischen 1 und 1000000 liegen.');
        }
      case StandardFormat():
        break;
      case JeopardyFormat(:final board):
        errors.addAll(_jeopardyValidationErrors(board, questions));
    }
    return List.unmodifiable(errors);
  }

  /// Throws a [QuizValidationException] when this quiz cannot be persisted.
  void validate() {
    final errors = validationErrors();
    if (errors.isNotEmpty) throw QuizValidationException(errors);
  }

  /// Returns a copy with selected fields replaced.
  Quiz copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    String? category,
    List<Question>? questions,
    List<Team>? teams,
    QuizFormat? format,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Quiz(
    schemaVersion: schemaVersion ?? this.schemaVersion,
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    category: category ?? this.category,
    questions: questions ?? this.questions,
    teams: teams ?? this.teams,
    format: format ?? this.format,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Serializes this complete quiz as one standalone document.
  JsonMap toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'questions': questions
        .map((question) => question.toJson())
        .toList(growable: false),
    'teams': teams.map((team) => team.toJson()).toList(growable: false),
    'format': format.toJson(),
    'createdAtMicros': createdAt.toUtc().microsecondsSinceEpoch,
    'updatedAtMicros': updatedAt.toUtc().microsecondsSinceEpoch,
  };

  @override
  List<Object?> get props => [
    schemaVersion,
    id,
    name,
    description,
    category,
    questions,
    teams,
    format,
    createdAt,
    updatedAt,
  ];
}

/// A quiz file that requires a newer version of Quizmo.
final class QuizSchemaUpdateRequiredException extends JsonContractException {
  /// Creates an update request for an unsupported newer schema.
  QuizSchemaUpdateRequiredException({
    required this.requiredVersion,
    required this.supportedVersion,
  }) : super(
         'Unsupported quiz schemaVersion $requiredVersion. '
         'This app supports up to $supportedVersion. '
         'Update Quizmo, then import this file again.',
       );

  /// Schema version required by the file.
  final int requiredVersion;

  /// Newest schema version supported by the installed app.
  final int supportedVersion;
}

void _addDuplicateIdError(
  List<String> errors,
  Iterable<String> ids,
  String itemLabel,
) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) errors.add('Duplicate $itemLabel ID "$id".');
  }
}

List<String> _jeopardyValidationErrors(
  JeopardyBoard board,
  List<Question> questions,
) {
  final errors = [...board.validationErrors()];
  final known = {for (final question in questions) question.id};
  for (final id in board.questionIds) {
    if (!known.contains(id)) {
      errors.add('The Jeopardy board references unknown question "$id".');
    }
  }
  return errors;
}

List<String> _questionValidationErrors(Question question) => [
  if (question.media.length + question.solutionMedia.length > 10)
    'Maximal zehn Medien pro Frage.',
  for (final media in [...question.media, ...question.solutionMedia]) ...[
    ...media.validationErrors,
    if (media.asset != null && media.asset!.data == null)
      'Medien-Datei fehlt im Quiz.',
  ],
  ...switch (question) {
    MultipleChoiceQuestion(
      :final id,
      :final prompt,
      :final timeLimit,
      :final options,
      :final solutionOptionIds,
      :final allowMultipleAnswers,
    ) =>
      _multipleChoiceValidationErrors(
        id: id,
        prompt: prompt,
        timeLimit: timeLimit,
        options: options,
        correctOptionIds: solutionOptionIds,
        allowMultipleAnswers: allowMultipleAnswers,
      ),
    ShortAnswerQuestion() ||
    OrderingQuestion() ||
    MatchingQuestion() ||
    EstimationQuestion() ||
    TrueFalseQuestion() => [
      ..._baseQuestionValidationErrors(
        id: question.id,
        prompt: question.prompt,
        timeLimit: question.timeLimit,
      ),
      ...question.contentErrors,
    ],
    BuzzerQuestion(:final id, :final prompt, :final timeLimit) => [
      ..._baseQuestionValidationErrors(
        id: id,
        prompt: prompt,
        timeLimit: timeLimit,
      ),
      ...question.contentErrors,
    ],
  },
];

List<String> _multipleChoiceValidationErrors({
  required String id,
  required String prompt,
  required Duration timeLimit,
  required List<AnswerOption> options,
  required List<String> correctOptionIds,
  required bool allowMultipleAnswers,
}) {
  final errors = _baseQuestionValidationErrors(
    id: id,
    prompt: prompt,
    timeLimit: timeLimit,
  );
  if (options.length < 2) {
    errors.add('Multiple-choice question "$id" needs at least two options.');
  }
  _addDuplicateIdError(errors, options.map((option) => option.id), 'option');
  for (final option in options) {
    if (option.id.trim().isEmpty) {
      errors.add('An option ID in question "$id" must not be empty.');
    }
    if (option.label.trim().isEmpty) {
      errors.add('Option "${option.id}" in question "$id" needs a label.');
    }
  }
  if (correctOptionIds.isEmpty ||
      correctOptionIds.toSet().length != correctOptionIds.length ||
      (!allowMultipleAnswers && correctOptionIds.length != 1) ||
      !correctOptionIds.every(
        (id) => options.any((option) => option.id == id),
      )) {
    errors.add(
      'Multiple-choice question "$id" needs a correctOptionId from its options.',
    );
  }
  return errors;
}

List<String> _baseQuestionValidationErrors({
  required String id,
  required String prompt,
  required Duration timeLimit,
}) {
  final errors = <String>[];
  if (id.trim().isEmpty) errors.add('A question ID must not be empty.');
  if (prompt.trim().isEmpty) errors.add('Question "$id" needs a prompt.');
  if (timeLimit <= Duration.zero) {
    errors.add('Question "$id" needs a positive time limit.');
  }
  return errors;
}
