/// Changes the kind of an existing question in the editor: what fits is taken
/// over, nothing is guessed, and everything that gets lost is listed first.
library;

import 'json.dart';
import 'question.dart';

/// A text for the host: a translation key with its arguments.
typedef ConversionText = ({String key, List<Object?> args});

/// The question of the new kind and what the change costs.
final class QuestionConversion {
  const QuestionConversion({
    required this.question,
    this.lost = const [],
    this.todo = const [],
    this.notes = const [],
  });

  /// Same id and every shared field; kind specific content as far as it fits.
  final Question question;

  /// Content that is emptied or removed.
  final List<ConversionText> lost;

  /// What has to be filled in afterwards.
  final List<ConversionText> todo;

  /// Changes of meaning worth knowing.
  final List<ConversionText> notes;

  bool get losesSomething => lost.isNotEmpty;
}

/// Kind-neutral content every kind can deliver and be built from.
final class _Essence {
  _Essence({
    this.answers = const [],
    this.options = const [],
    this.correctOptions = const {},
    this.items = const [],
    this.number,
    this.unit = '',
    this.truth,
  });

  /// Accepted answers as text.
  final List<String> answers;

  /// Answer options and the indices of the right ones.
  final List<String> options;
  final Set<int> correctOptions;

  /// Elements (ordering items or left terms of a matching).
  final List<String> items;
  final double? number;
  final String unit;
  final bool? truth;
}

ConversionText _t(String key, [List<Object?> args = const []]) =>
    (key: key, args: args);

/// Reads "12 km", "1.234,5" or "1,234.5" as a number with its unit, `null`
/// when [text] is no clear number.
(double, String)? parseNumberWithUnit(String text) {
  final match = RegExp(r'^\s*([+-]?[\d.,\s]*\d)\s*([^\d\s.,][^\d]*)?\s*$')
      .firstMatch(text);
  if (match == null) return null;
  var digits = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  final comma = digits.lastIndexOf(',');
  final dot = digits.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    // The later one separates the decimals.
    digits = comma > dot
        ? digits.replaceAll('.', '').replaceAll(',', '.')
        : digits.replaceAll(',', '');
  } else if (comma >= 0 || dot >= 0) {
    final separator = comma >= 0 ? ',' : '.';
    final parts = digits.split(separator);
    if (parts.length > 2) {
      // Only thousands use a separator more than once.
      if (parts.skip(1).any((part) => part.length != 3)) return null;
      digits = parts.join();
    } else if (parts.last.length == 3) {
      // "10.000" or "1,234": thousands or decimals? Never guessed.
      return null;
    } else {
      digits = parts.join('.');
    }
  }
  final value = double.tryParse(digits);
  if (value == null || !value.isFinite) return null;
  return (value, (match.group(2) ?? '').trim());
}

bool? _truthOf(String text) => switch (text.trim().toLowerCase()) {
  'wahr' || 'true' || 'richtig' || 'ja' || 'yes' => true,
  'falsch' || 'false' || 'nein' || 'no' => false,
  _ => null,
};

_Essence _essenceOf(Question question) => switch (question) {
  MultipleChoiceQuestion(:final options, :final solutionOptionIds) => _Essence(
    options: [for (final option in options) option.label],
    correctOptions: {
      for (final (index, option) in options.indexed)
        if (solutionOptionIds.contains(option.id)) index,
    },
    items: [for (final option in options) option.label],
    answers: [
      for (final option in options)
        if (solutionOptionIds.contains(option.id)) option.label,
    ],
  ),
  ShortAnswerQuestion(:final acceptedAnswers) => _Essence(
    answers: [
      for (final answer in acceptedAnswers ?? const <String>[])
        if (answer.trim().isNotEmpty) answer.trim(),
    ],
  ),
  BuzzerQuestion(:final expectedAnswer) => _Essence(
    answers: [
      if (expectedAnswer != null && expectedAnswer.trim().isNotEmpty)
        expectedAnswer.trim(),
    ],
  ),
  OrderingQuestion(:final items, :final correctOrder) => _Essence(
    items: [
      for (final id in correctOrder ?? [for (final item in items) item.id])
        items.firstWhere((item) => item.id == id).label,
    ],
    options: [for (final item in items) item.label],
  ),
  MatchingQuestion(:final leftItems) => _Essence(
    items: [for (final item in leftItems) item.label],
    options: [for (final item in leftItems) item.label],
  ),
  EstimationQuestion(:final correctValue, :final unit) => _Essence(
    number: correctValue,
    unit: unit,
    answers: [if (correctValue != null) question.valueLabel(correctValue)],
  ),
  TrueFalseQuestion(:final correctAnswer) => _Essence(
    truth: correctAnswer,
    options: const ['Wahr', 'Falsch'],
    correctOptions: {if (correctAnswer != null) correctAnswer ? 0 : 1},
    answers: [if (correctAnswer != null) correctAnswer ? 'Wahr' : 'Falsch'],
  ),
  LocationQuestion() => _Essence(),
};

/// [from] as a question of the kind of [kind] (any question of that kind,
/// e.g. a template). With [withSolution] false (Biggest Snowflake) no
/// solution is created or reported as lost.
QuestionConversion convertQuestion(
  Question from,
  Question kind, {
  bool withSolution = true,
}) {
  if (from.runtimeType == kind.runtimeType) {
    return QuestionConversion(question: from);
  }
  final essence = _essenceOf(from);
  final lost = <ConversionText>[];
  final todo = <ConversionText>[];
  final notes = <ConversionText>[];
  String list(Iterable<String> values) => values.join(', ');

  // What the old kind has and the new one cannot keep.
  void lose(bool condition, String key, [List<Object?> args = const []]) {
    if (condition) lost.add(_t(key, args));
  }

  final JsonMap specific;
  switch (kind) {
    case ShortAnswerQuestion():
      final answers = switch (from) {
        // Several accepted answers of a buzzer are spellings: only the first.
        _ => essence.answers,
      };
      specific = {
        'acceptedAnswers': withSolution ? answers : null,
        'maxEdits': 1,
        'manualGrading': false,
      };
      if (withSolution && answers.isEmpty) {
        todo.add(_t('Mindestens eine akzeptierte Antwort angeben.'));
      }
      if (from is MultipleChoiceQuestion && essence.correctOptions.length > 1) {
        notes.add(
          _t(
            'Die {0} richtigen Optionen werden akzeptierte Antworten; künftig genügt jede einzeln.',
            [essence.correctOptions.length],
          ),
        );
      }
    case BuzzerQuestion():
      final answer = from is MultipleChoiceQuestion
          ? essence.answers.join(' / ')
          : essence.answers.firstOrNull;
      specific = {
        'expectedAnswer': withSolution ? answer : null,
        'lockOutOnMiss': true,
        'hostEndsRound': false,
        'retryLimit': null,
      };
      if (from is ShortAnswerQuestion && essence.answers.length > 1) {
        lose(true, 'Weitere akzeptierte Antworten: {0}', [
          list(essence.answers.skip(1)),
        ]);
      }
    case MultipleChoiceQuestion():
      final options = switch (from) {
        ShortAnswerQuestion() ||
        BuzzerQuestion() ||
        EstimationQuestion() => essence.answers.take(1).toList(),
        _ => essence.options,
      };
      final correct = switch (from) {
        ShortAnswerQuestion() ||
        BuzzerQuestion() ||
        EstimationQuestion() => options.isEmpty ? <int>{} : {0},
        TrueFalseQuestion() ||
        MultipleChoiceQuestion() => essence.correctOptions,
        _ => <int>{},
      };
      if (from is ShortAnswerQuestion && essence.answers.length > 1) {
        lose(true, 'Weitere akzeptierte Antworten: {0}', [
          list(essence.answers.skip(1)),
        ]);
      }
      final ids = [for (var i = 0; i < options.length; i++) 'option-${i + 1}'];
      specific = {
        'options': [
          for (final (i, label) in options.indexed)
            {'id': ids[i], 'label': label},
        ],
        'correctOptionId': withSolution && correct.length == 1
            ? ids[correct.single]
            : null,
        'correctOptionIds': null,
        'allowMultipleAnswers': false,
      };
      if (options.length < 2) {
        todo.add(_t('Weitere Antwortmöglichkeiten ergänzen.'));
      }
      if (withSolution && correct.isEmpty) {
        todo.add(_t('Die richtige Antwort wählen.'));
      }
    case OrderingQuestion():
      final items = essence.items;
      specific = {
        'items': [
          for (final (i, label) in items.indexed)
            {'id': 'item-${i + 1}', 'label': label},
        ],
        'correctOrder': null,
      };
      if (items.length < 2) todo.add(_t('Mindestens zwei Elemente angeben.'));
      if (withSolution) todo.add(_t('Die richtige Reihenfolge festlegen.'));
    case MatchingQuestion():
      final items = essence.items;
      specific = {
        'leftItems': [
          for (final (i, label) in items.indexed)
            {'id': 'left-${i + 1}', 'label': label},
        ],
        'rightItems': const <Object?>[],
        'correctPairs': null,
      };
      todo.add(_t('Rechte Elemente und Paare ergänzen.'));
    case EstimationQuestion():
      final parsed = switch (from) {
        ShortAnswerQuestion() || BuzzerQuestion() || MultipleChoiceQuestion()
            when essence.answers.isNotEmpty &&
                (from is! MultipleChoiceQuestion ||
                    essence.correctOptions.length == 1) =>
          () {
            final values = [
              for (final answer in essence.answers) parseNumberWithUnit(answer),
            ];
            // Unambiguous: every spelling says the same number.
            return values.every(
                  (value) =>
                      value != null &&
                      value.$1 == values.first!.$1 &&
                      value.$2 == values.first!.$2,
                )
                ? values.first
                : null;
          }(),
        _ => null,
      };
      specific = {
        'correctValue': withSolution ? parsed?.$1 : null,
        'zeroScale': 1.0,
        'unit': parsed?.$2 ?? '',
      };
      if (withSolution && parsed == null) {
        todo.add(_t('Die Zielzahl angeben.'));
        lose(
          essence.answers.isNotEmpty,
          'Antwort, die keine eindeutige Zahl ist: {0}',
          [list(essence.answers)],
        );
      }
    case TrueFalseQuestion():
      final truth = switch (from) {
        ShortAnswerQuestion() || BuzzerQuestion() || MultipleChoiceQuestion()
            when essence.answers.length == 1 =>
          _truthOf(essence.answers.single),
        _ => null,
      };
      specific = {'correctAnswer': withSolution ? truth : null};
      if (withSolution && truth == null) {
        todo.add(_t('Wahr oder Falsch als Lösung wählen.'));
      }
    case LocationQuestion():
      specific = const LocationQuestion(id: '', prompt: '').toJson()
        ..removeWhere(
          (key, _) => !const {
            'target',
            'targetLabel',
            'fullPointsKm',
            'zeroPointsKm',
            'startCenter',
            'startZoom',
          }.contains(key),
        );
      if (withSolution) todo.add(_t('Gültigen Zielort angeben.'));
  }

  // Losses of the old kind that the new one does not take over.
  switch (from) {
    case MultipleChoiceQuestion(:final options, :final solutionOptionIds):
      final wrong = [
        for (final option in options)
          if (!solutionOptionIds.contains(option.id)) option.label,
      ];
      final keepsOptions = kind is OrderingQuestion || kind is MatchingQuestion;
      lose(
        withSolution && wrong.isNotEmpty && !keepsOptions,
        '{0} falsche Antwortmöglichkeiten: {1}',
        [wrong.length, list(wrong)],
      );
      lose(
        !withSolution && !keepsOptions && kind is! MultipleChoiceQuestion,
        'Antwortmöglichkeiten: {0}',
        [list(essence.options)],
      );
      lose(
        withSolution && keepsOptions && solutionOptionIds.isNotEmpty,
        'Die richtige Antwort ({0})',
        [list(essence.answers)],
      );
      lose(from.allowMultipleAnswers, 'Mehrfachauswahl');
    case ShortAnswerQuestion(:final maxEdits, :final manualGrading):
      lose(
        maxEdits != 1 && kind is! ShortAnswerQuestion,
        'Erlaubte Tippfehler: {0}',
        [maxEdits],
      );
      lose(manualGrading, 'Wertung durch die Spielleitung');
    case BuzzerQuestion(
      :final lockOutOnMiss,
      :final hostEndsRound,
      :final retryLimit,
    ):
      lose(!lockOutOnMiss, 'Erneutes Buzzern nach Fehlversuch');
      lose(hostEndsRound, 'Spielleitung beendet die Runde');
      lose(retryLimit != null, 'Wiederholungen: {0}', [retryLimit]);
    case OrderingQuestion(:final correctOrder):
      lose(
        withSolution && correctOrder != null && kind is! OrderingQuestion,
        'Die richtige Reihenfolge',
      );
      lose(
        kind is ShortAnswerQuestion ||
            kind is BuzzerQuestion ||
            kind is EstimationQuestion ||
            kind is TrueFalseQuestion ||
            kind is LocationQuestion,
        'Elemente: {0}',
        [list(essence.items)],
      );
    case MatchingQuestion(:final rightItems, :final correctPairs):
      lose(rightItems.isNotEmpty, 'Rechte Elemente: {0}', [
        list([for (final item in rightItems) item.label]),
      ]);
      lose(withSolution && correctPairs != null, 'Die Paare der Zuordnung');
      lose(
        !(kind is MultipleChoiceQuestion || kind is OrderingQuestion),
        'Linke Elemente: {0}',
        [list(essence.items)],
      );
    case EstimationQuestion(:final unit, :final zeroScale, :final hasTolerance):
      lose(
        kind is! ShortAnswerQuestion &&
            kind is! BuzzerQuestion &&
            kind is! MultipleChoiceQuestion &&
            withSolution &&
            essence.number != null,
        'Zielzahl: {0}',
        [essence.answers.firstOrNull],
      );
      lose(unit.isNotEmpty && kind is! EstimationQuestion, 'Einheit: {0}', [
        unit,
      ]);
      lose(zeroScale != 1, 'Skala für die Teilpunkte');
      lose(hasTolerance, 'Toleranzbereich');
    case TrueFalseQuestion(:final correctAnswer):
      lose(
        withSolution &&
            correctAnswer != null &&
            (kind is OrderingQuestion ||
                kind is MatchingQuestion ||
                kind is EstimationQuestion ||
                kind is LocationQuestion),
        'Die Lösung ({0})',
        [correctAnswer! ? 'Wahr' : 'Falsch'],
      );
    case LocationQuestion(:final target, :final targetLabel):
      lose(withSolution && target != null, 'Zielort: {0}', [
        targetLabel.isEmpty ? target?.label : targetLabel,
      ]);
      lose(true, 'Radien und Startausschnitt der Karte');
  }

  final base = from.toJson()
    ..removeWhere(
      (key, _) => !const {
        'id',
        'prompt',
        'timeLimitMs',
        'softTimeLimit',
        'category',
        'adminNotes',
        'media',
        'solutionMedia',
        'scoringRule',
        'hints',
      }.contains(key),
    );
  final typeOfKind = kind.toJson()['type'];
  var question = Question.fromJson({...base, 'type': typeOfKind, ...specific});
  if (!withSolution) question = question.withoutSolution();
  return QuestionConversion(
    question: question,
    lost: lost,
    todo: todo,
    notes: notes,
  );
}

/// [kindSpecific] (a question of the target kind, e.g. remembered from an
/// earlier change) with the shared fields of [current].
Question withSharedFields(Question kindSpecific, Question current) {
  final shared = current.toJson()
    ..removeWhere(
      (key, _) => !const {
        'id',
        'prompt',
        'timeLimitMs',
        'softTimeLimit',
        'category',
        'adminNotes',
        'media',
        'solutionMedia',
        'scoringRule',
        'hints',
      }.contains(key),
    );
  return Question.fromJson({...kindSpecific.toJson(), ...shared});
}
