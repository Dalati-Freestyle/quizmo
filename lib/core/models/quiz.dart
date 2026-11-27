/// The persisted definition of a reusable quiz.
library;

import 'package:equatable/equatable.dart';

import '../engine/scoring_rules.dart';
import 'jeopardy.dart';
import 'info_slide.dart';
import 'joker.dart';
import 'json.dart';
import 'question.dart';
import 'question_hint.dart';
import 'quiz_format.dart';
import 'team.dart';
import 'team_color.dart';
import 'markdown_text.dart';

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
    this.jokers = const [],
    this.slides = const [],
    this.schemaVersion = currentSchemaVersion,
  });

  /// The newest file format this version of Quizmo can read and write.
  static const int currentSchemaVersion = 16;

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
      7 => Quiz._fromJsonV7(json),
      8 => Quiz._fromJsonV8(json),
      9 => Quiz._fromJsonV9(json),
      10 => Quiz._fromJsonV10(json),
      11 => Quiz._fromJsonV11(json),
      12 => Quiz._fromJsonV12(json),
      13 => Quiz._fromJsonV13(json),
      14 => Quiz._fromJsonV14(json),
      15 => Quiz._fromJsonV15(json),
      16 => Quiz._fromJsonV16(json),
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
    final format = json.readObjectOrNull('format');
    return Quiz._fromJsonV7({
      ...json,
      if (format?['type'] == 'standard')
        'format': {
          ...format!,
          'revealMode': SolutionRevealMode.afterEachQuestion.name,
        },
    });
  }

  /// Schema 7 and older always had a positive time limit; 0 (no limit)
  /// only exists from schema 8 on, so it stays invalid in older files.
  factory Quiz._fromJsonV7(JsonMap json) {
    for (final question in json.readList('questions', (q) => q)) {
      if (question.readInt('timeLimitMs') <= 0) {
        throw JsonContractException(
          'Question "${question['id']}" needs a positive time limit.',
        );
      }
    }
    return Quiz._fromJsonV8(json);
  }

  /// Schema 8 and older stored any ARGB team colour; schema 9 stores the name
  /// of a palette colour, so older colours move to the nearest one.
  factory Quiz._fromJsonV8(JsonMap json) => Quiz._fromJsonV9({
    ...json,
    'teams': json.readList(
      'teams',
      (team) => {
        for (final entry in team.entries)
          if (entry.key != 'colorValue') entry.key: entry.value,
        'color': TeamColor.nearest(team.readInt('colorValue')).name,
      },
    ),
  });

  /// Schema 9 has no "Biggest Snowflake" format; everything else is equal.
  factory Quiz._fromJsonV9(JsonMap json) {
    if (json.readObjectOrNull('format')?['type'] == 'snowflake') {
      throw const JsonContractException(
        'The "snowflake" format needs schemaVersion 10.',
      );
    }
    return Quiz._fromJsonV10(json);
  }

  /// Schema 10 limited each uploaded file to 20 MiB and all media of a quiz to
  /// 90 MiB; schema 11 drops both limits. Files written by older apps always
  /// respect them, so they import unchanged.
  factory Quiz._fromJsonV10(JsonMap json) => Quiz._fromJsonV11(json);

  /// Schema 11 has no stake limits in the poker format (every team could bet
  /// anything from 0 to all its chips, which the defaults keep) and no jokers.
  factory Quiz._fromJsonV11(JsonMap json) {
    final format = json.readObjectOrNull('format');
    if (format != null &&
        ((format['minStake'] ?? 0) != 0 || format['maxStake'] != null)) {
      throw const JsonContractException(
        'Poker stake limits need schemaVersion 12.',
      );
    }
    if (json['jokers'] case final List<Object?> jokers when jokers.isNotEmpty) {
      throw const JsonContractException('Jokers need schemaVersion 12.');
    }
    if (json['slides'] case final List<Object?> slides when slides.isNotEmpty) {
      throw const JsonContractException(
        'Interstitial slides need schemaVersion 12.',
      );
    }
    return Quiz._fromJsonV12(json);
  }

  /// Schema 12 has no hints; questions without hints are equal in schema 13.
  /// Right items of a matching question with the same label used to be told
  /// apart; from schema 13 on they are interchangeable, which also applies to
  /// imported older files.
  factory Quiz._fromJsonV12(JsonMap json) {
    for (final question in json.readList('questions', (q) => q)) {
      if (question['hints'] case final List<Object?> hints
          when hints.isNotEmpty) {
        throw const JsonContractException('Hints need schemaVersion 13.');
      }
    }
    return Quiz._fromJsonV13(json);
  }

  /// Schema 13 has no tolerance for estimation questions; without one they are
  /// scored exactly as before.
  factory Quiz._fromJsonV13(JsonMap json) {
    for (final question in json.readList('questions', (q) => q)) {
      if (question['minAccepted'] != null || question['maxAccepted'] != null) {
        throw const JsonContractException(
          'Estimation tolerances need schemaVersion 14.',
        );
      }
    }
    return Quiz._fromJsonV14(json);
  }

  /// Schema 14 and older store plain text: from schema 15 on prompts, host
  /// notes, hint texts and slide texts are Markdown. Characters that would
  /// format something are escaped, so older quizzes look exactly as before.
  factory Quiz._fromJsonV14(JsonMap json) => Quiz._fromJsonV15({
    ...json,
    'questions': json.readList('questions', escapeQuestionTexts),
    if (json['slides'] != null)
      'slides': json.readList('slides', escapeSlideText),
  });

  /// Schema 15 has no map questions; everything else is equal.
  factory Quiz._fromJsonV15(JsonMap json) {
    for (final question in json.readList('questions', (q) => q)) {
      if (question['type'] == 'location') {
        throw const JsonContractException(
          'Map questions need schemaVersion 16.',
        );
      }
    }
    return Quiz._fromJsonV16(json);
  }

  factory Quiz._fromJsonV16(JsonMap json) {
    // Files written before formats existed have no entry: plain quiz.
    final format = switch (json.readObjectOrNull('format')) {
      final JsonMap value => QuizFormat.fromJson(value),
      null => const StandardFormat(),
    };
    final quiz = Quiz(
      schemaVersion: currentSchemaVersion,
      id: json.readString('id'),
      name: json.readString('name'),
      description: json.readString('description'),
      category: json.readString('category'),
      questions: [
        // A snowflake quiz is played without solutions; a file that still
        // carries some (e.g. converted by hand) is normalised.
        for (final question in json.readList('questions', Question.fromJson))
          format is SnowflakeFormat ? question.withoutSolution() : question,
      ],
      teams: json.readList('teams', _teamFromQuizJson),
      format: format,
      jokers: json['jokers'] == null
          ? const []
          : json.readList('jokers', Joker.fromJson),
      slides: json['slides'] == null
          ? const []
          : json.readList('slides', InfoSlide.fromJson),
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

  /// Jokers every team may play; empty for a quiz without jokers.
  final List<Joker> jokers;

  /// Unscored interstitial slides, each placed before a question.
  final List<InfoSlide> slides;

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
    for (final question in questions) {
      errors.addAll(
        _questionValidationErrors(
          question,
          needsSolution: format is! SnowflakeFormat,
        ),
      );
    }
    switch (format) {
      case PokerFormat(:final startingChips, :final minStake, :final maxStake):
        if (startingChips < 1 || startingChips > 1000000) {
          errors.add('Startchips müssen zwischen 1 und 1000000 liegen.');
        }
        if (minStake < 0 || minStake > startingChips) {
          errors.add(
            'Der Mindesteinsatz muss zwischen 0 und den Startchips liegen.',
          );
        }
        if (maxStake != null &&
            (maxStake < 1 || maxStake < minStake || maxStake > startingChips)) {
          errors.add(
            'Der Höchsteinsatz muss zwischen dem Mindesteinsatz (mindestens 1) '
            'und den Startchips liegen.',
          );
        }
      case StandardFormat():
        break;
      case SnowflakeFormat():
        for (final question in questions) {
          if (!question.supportsUniqueness) {
            errors.add(
              'Biggest Snowflake unterstützt die Frage "${question.id}" '
              'nicht: nur Multiple Choice, Wahr/Falsch, Reihenfolge und '
              'Zuordnung sind möglich.',
            );
          } else if (question.hasSolution) {
            errors.add(
              'Biggest Snowflake speichert keine Lösung: Frage '
              '"${question.id}" enthält eine.',
            );
          }
        }
      case JeopardyFormat(:final board):
        errors.addAll(_jeopardyValidationErrors(board, questions));
    }
    for (final joker in jokers) {
      errors.addAll(joker.validationErrors(format));
    }
    if (jokers.map((joker) => joker.id).toSet().length != jokers.length) {
      errors.add('Jeder Joker darf nur einmal pro Quiz vorkommen.');
    }
    final questionIds = questions.map((question) => question.id).toSet();
    for (final slide in slides) {
      errors.addAll(slide.validationErrors(questionIds));
    }
    if (slides.map((slide) => slide.id).toSet().length != slides.length) {
      errors.add('Jede Zwischenfolie braucht eine eigene ID.');
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
    List<Joker>? jokers,
    List<InfoSlide>? slides,
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
    jokers: jokers ?? this.jokers,
    slides: slides ?? this.slides,
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
    'teams': teams.map(_teamToQuizJson).toList(growable: false),
    'format': format.toJson(),
    'jokers': jokers.map((joker) => joker.toJson()).toList(growable: false),
    'slides': slides.map((slide) => slide.toJson()).toList(growable: false),
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
    jokers,
    slides,
    createdAt,
    updatedAt,
  ];
}

/// Reads a team of a quiz file: its colour is a palette name (schema 9).
Team _teamFromQuizJson(JsonMap json) {
  final name = json.readString('color');
  final color = TeamColor.byName(name);
  if (color == null) {
    throw JsonContractException(
      'Unknown team colour "$name". Use one of: '
      '${TeamColor.values.map((c) => c.name).join(', ')}.',
    );
  }
  return Team.fromJson({
    for (final entry in json.entries)
      if (entry.key != 'color') entry.key: entry.value,
    'colorValue': color.argb,
  });
}

/// Writes a team of a quiz file with the name of its palette colour.
JsonMap _teamToQuizJson(Team team) => {
  for (final entry in team.toJson().entries)
    if (entry.key != 'colorValue') entry.key: entry.value,
  'color': TeamColor.nearest(team.colorValue).name,
};

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

List<String> _questionValidationErrors(
  Question question, {
  required bool needsSolution,
}) => [
  if (question.scoringRule is SpeedBonusRule && !question.hasTimeLimit)
    'Question "${question.id}" needs a time limit for the speed bonus.',
  if (question.media.length + question.solutionMedia.length > 10)
    'Maximal zehn Medien pro Frage.',
  for (final media in [...question.media, ...question.solutionMedia]) ...[
    ...media.validationErrors,
    if (media.asset != null && media.asset!.data == null)
      'Medien-Datei fehlt im Quiz.',
  ],
  if (question.hints.length > QuestionHint.maxPerQuestion)
    'Maximal zehn Tipps pro Frage.',
  for (final hint in question.hints) ...[
    ...hint.validationErrors,
    for (final media in hint.media)
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
        needsSolution: needsSolution,
      ),
    ShortAnswerQuestion() ||
    OrderingQuestion() ||
    MatchingQuestion() ||
    LocationQuestion() ||
    EstimationQuestion() ||
    TrueFalseQuestion() => [
      ..._baseQuestionValidationErrors(
        id: question.id,
        prompt: question.prompt,
        timeLimit: question.timeLimit,
      ),
      ...question.structureErrors,
      if (needsSolution) ...question.solutionErrors,
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
  required bool needsSolution,
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
  if (needsSolution &&
      (correctOptionIds.isEmpty ||
          correctOptionIds.toSet().length != correctOptionIds.length ||
          (!allowMultipleAnswers && correctOptionIds.length != 1) ||
          !correctOptionIds.every(
            (id) => options.any((option) => option.id == id),
          ))) {
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
  if (isBlankMarkdown(prompt)) {
    errors.add('Question "$id" needs a prompt.');
  }
  if (timeLimit < Duration.zero) {
    errors.add('Question "$id" must not have a negative time limit.');
  }
  return errors;
}

/// [question] (JSON of schema 14 or older) with its plain texts escaped for
/// Markdown.
JsonMap escapeQuestionTexts(JsonMap question) => {
  ...question,
  if (question['prompt'] case final String prompt)
    'prompt': escapeMarkdown(prompt),
  if (question['adminNotes'] case final String notes)
    'adminNotes': escapeMarkdown(notes),
  if (question['hints'] case final List<Object?> hints)
    'hints': [
      for (final hint in hints)
        if (hint is JsonMap && hint['text'] is String)
          {...hint, 'text': escapeMarkdown(hint['text']! as String)}
        else
          hint,
    ],
};

/// [slide] (JSON of schema 14 or older) with its plain text escaped.
JsonMap escapeSlideText(JsonMap slide) => {
  ...slide,
  if (slide['text'] case final String text) 'text': escapeMarkdown(text),
};
