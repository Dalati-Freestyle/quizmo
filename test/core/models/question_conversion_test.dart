import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

const _shared = (
  prompt: '**Was?**',
  category: 'Kat',
  notes: 'Notiz',
  hint: QuestionHint(text: 'Tipp', cost: 2),
  limit: Duration(seconds: 42),
);

const _geo = GeoAttachment(latitude: 1, longitude: 2, zoom: 3);

Question withShared(Question q) => Question.fromJson({
  ...q.toJson(),
  'prompt': _shared.prompt,
  'category': _shared.category,
  'adminNotes': _shared.notes,
  'timeLimitMs': _shared.limit.inMilliseconds,
  'softTimeLimit': true,
  'media': [_geo.toJson()],
  'solutionMedia': [_geo.toJson()],
  'hints': [_shared.hint.toJson()],
});

final _kinds = <Question>[
  withShared(
    const MultipleChoiceQuestion(
      id: 'q',
      prompt: '',
      options: [
        AnswerOption(id: 'a', label: '12 km'),
        AnswerOption(id: 'b', label: 'Bonn'),
        AnswerOption(id: 'c', label: 'Köln'),
      ],
      correctOptionId: 'a',
    ),
  ),
  withShared(
    const ShortAnswerQuestion(
      id: 'q',
      prompt: '',
      acceptedAnswers: ['Berlin', 'Berlinn'],
      maxEdits: 2,
    ),
  ),
  withShared(const BuzzerQuestion(id: 'q', prompt: '', expectedAnswer: 'Wahr')),
  withShared(
    const OrderingQuestion(
      id: 'q',
      prompt: '',
      items: [
        AnswerOption(id: 'x', label: 'Erst'),
        AnswerOption(id: 'y', label: 'Dann'),
      ],
      correctOrder: ['x', 'y'],
    ),
  ),
  withShared(
    const MatchingQuestion(
      id: 'q',
      prompt: '',
      leftItems: [
        AnswerOption(id: 'l1', label: 'DE'),
        AnswerOption(id: 'l2', label: 'FR'),
      ],
      rightItems: [
        AnswerOption(id: 'r1', label: 'Berlin'),
        AnswerOption(id: 'r2', label: 'Paris'),
      ],
      correctPairs: {'l1': 'r1', 'l2': 'r2'},
    ),
  ),
  withShared(
    const EstimationQuestion(
      id: 'q',
      prompt: '',
      correctValue: 330,
      unit: 'm',
      minAccepted: 320,
      maxAccepted: 340,
    ),
  ),
  withShared(
    const TrueFalseQuestion(id: 'q', prompt: '', correctAnswer: false),
  ),
  withShared(
    const LocationQuestion(
      id: 'q',
      prompt: '',
      target: GeoPoint(48.8, 2.3),
      targetLabel: 'Paris',
    ),
  ),
];

/// Every text of the template that could be an example value.
const _examples = [
  'Option A',
  'Option B',
  'Antwort',
  'Erstes',
  'Zweites',
  'Deutschland',
  'Berlin ',
];

String key(ConversionText text) => text.key;

void main() {
  test('every combination keeps id and shared fields and never guesses', () {
    for (final from in _kinds) {
      for (final kind in _kinds) {
        final result = convertQuestion(from, kind);
        final q = result.question;
        final reason = '${from.kindLabel} → ${kind.kindLabel}';
        expect(q.runtimeType, kind.runtimeType, reason: reason);
        expect(q.id, 'q', reason: reason);
        expect(q.prompt, _shared.prompt, reason: reason);
        expect(q.category, _shared.category, reason: reason);
        expect(q.adminNotes, _shared.notes, reason: reason);
        expect(q.timeLimit, _shared.limit, reason: reason);
        expect(q.softTimeLimit, isTrue, reason: reason);
        expect(q.media, [_geo], reason: reason);
        expect(q.solutionMedia, [_geo], reason: reason);
        expect(q.hints, [_shared.hint], reason: reason);
        expect(q.scoringRule, from.scoringRule, reason: reason);
        final json = '${q.toJson()}';
        for (final example in _examples) {
          expect(
            json,
            isNot(contains("'$example'")),
            reason: '$reason $example',
          );
        }
        if (from.runtimeType != kind.runtimeType) {
          // Something always has to be filled in, or the solution was taken
          // over; an incomplete question can't be saved.
          expect(
            result.todo.isNotEmpty || q.contentErrors.isEmpty,
            isTrue,
            reason: reason,
          );
          if (result.todo.isNotEmpty) {
            final quiz = Quiz(
              id: 'quiz',
              name: 'Q',
              description: 'D',
              category: 'C',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              questions: [q],
            );
            expect(
              quiz.validationErrors(),
              isNotEmpty,
              reason: '$reason must stay invalid',
            );
          }
        } else {
          expect(q, from, reason: reason);
          expect(result.lost, isEmpty, reason: reason);
        }
        // The file round-trips unchanged.
        expect(Question.fromJson(q.toJson()), q, reason: reason);
      }
    }
  });

  T as<T>(Question q) => q as T;
  Question kindOf<T>() => _kinds.firstWhere((q) => q is T);

  test('solutions follow the table', () {
    final mc = kindOf<MultipleChoiceQuestion>();
    final short = as<ShortAnswerQuestion>(
      convertQuestion(mc, kindOf<ShortAnswerQuestion>()).question,
    );
    expect(short.acceptedAnswers, ['12 km']);
    final lostWrong = convertQuestion(mc, kindOf<ShortAnswerQuestion>()).lost;
    expect(
      lostWrong.map(key),
      contains('{0} falsche Antwortmöglichkeiten: {1}'),
    );
    expect(lostWrong.firstWhere((t) => t.key.contains('falsche')).args, [
      2,
      'Bonn, Köln',
    ]);
    final estimate = as<EstimationQuestion>(
      convertQuestion(mc, kindOf<EstimationQuestion>()).question,
    );
    expect((estimate.correctValue, estimate.unit), (12, 'km'));

    final fromText = kindOf<ShortAnswerQuestion>();
    expect(
      as<BuzzerQuestion>(
        convertQuestion(fromText, kindOf<BuzzerQuestion>()).question,
      ).expectedAnswer,
      'Berlin',
    );
    final choice = as<MultipleChoiceQuestion>(
      convertQuestion(fromText, kindOf<MultipleChoiceQuestion>()).question,
    );
    expect(choice.options.map((o) => o.label), ['Berlin']);
    expect(choice.correctOptionId, choice.options.single.id);
    expect(
      convertQuestion(fromText, kindOf<MultipleChoiceQuestion>()).todo.map(key),
      contains('Weitere Antwortmöglichkeiten ergänzen.'),
    );
    expect(
      as<EstimationQuestion>(
        convertQuestion(fromText, kindOf<EstimationQuestion>()).question,
      ).correctValue,
      isNull,
      reason: 'Berlin is no number',
    );

    final buzzer = kindOf<BuzzerQuestion>();
    expect(
      as<TrueFalseQuestion>(
        convertQuestion(buzzer, kindOf<TrueFalseQuestion>()).question,
      ).correctAnswer,
      isTrue,
    );

    final ordering = kindOf<OrderingQuestion>();
    final fromOrder = as<MultipleChoiceQuestion>(
      convertQuestion(ordering, kindOf<MultipleChoiceQuestion>()).question,
    );
    expect(fromOrder.options.map((o) => o.label), ['Erst', 'Dann']);
    expect(fromOrder.hasSolution, isFalse);
    final toMatch = as<MatchingQuestion>(
      convertQuestion(ordering, kindOf<MatchingQuestion>()).question,
    );
    expect(toMatch.leftItems.map((o) => o.label), ['Erst', 'Dann']);
    expect(toMatch.rightItems, isEmpty);

    final matching = kindOf<MatchingQuestion>();
    final lost = convertQuestion(matching, kindOf<OrderingQuestion>()).lost;
    expect(
      lost.map(key),
      containsAll(['Rechte Elemente: {0}', 'Die Paare der Zuordnung']),
    );

    final estimation = kindOf<EstimationQuestion>();
    expect(
      as<ShortAnswerQuestion>(
        convertQuestion(estimation, kindOf<ShortAnswerQuestion>()).question,
      ).acceptedAnswers,
      ['330 m'],
    );
    expect(
      convertQuestion(estimation, kindOf<ShortAnswerQuestion>()).lost.map(key),
      containsAll(['Einheit: {0}', 'Toleranzbereich']),
    );

    final truth = kindOf<TrueFalseQuestion>();
    final tfChoice = as<MultipleChoiceQuestion>(
      convertQuestion(truth, kindOf<MultipleChoiceQuestion>()).question,
    );
    expect(tfChoice.options.map((o) => o.label), ['Wahr', 'Falsch']);
    expect(tfChoice.solutionLabel, 'Falsch');
    expect(
      as<ShortAnswerQuestion>(
        convertQuestion(truth, kindOf<ShortAnswerQuestion>()).question,
      ).acceptedAnswers,
      ['Falsch'],
    );
  });

  test('numbers are read carefully', () {
    expect(parseNumberWithUnit('12 km'), (12.0, 'km'));
    expect(parseNumberWithUnit('1.234,5'), (1234.5, ''));
    expect(parseNumberWithUnit('1,234.5 m'), (1234.5, 'm'));
    expect(parseNumberWithUnit('3,5'), (3.5, ''));
    expect(parseNumberWithUnit('10.000.000'), (10000000.0, ''));
    expect(parseNumberWithUnit('10.000'), isNull, reason: 'ambiguous');
    expect(parseNumberWithUnit('-7'), (-7.0, ''));
    expect(parseNumberWithUnit('ca. 12'), isNull);
    expect(parseNumberWithUnit('12 oder 13'), isNull);
  });

  test('without solutions (snowflake) nothing is created or lost', () {
    final mc = kindOf<MultipleChoiceQuestion>().withoutSolution();
    final result = convertQuestion(
      mc,
      const OrderingQuestion(id: '', prompt: ''),
      withSolution: false,
    );
    expect(result.question.hasSolution, isFalse);
    expect(result.lost.map(key), isNot(contains('Die richtige Antwort ({0})')));
  });

  test('switching back restores the old kind with new shared fields', () {
    final original = kindOf<MatchingQuestion>();
    final changed = Question.fromJson({
      ...convertQuestion(
        original,
        kindOf<ShortAnswerQuestion>(),
      ).question.toJson(),
      'prompt': 'Neu',
    });
    final back = withSharedFields(original, changed);
    expect(back, isA<MatchingQuestion>());
    expect(
      (back as MatchingQuestion).correctPairs,
      (original as MatchingQuestion).correctPairs,
    );
    expect(back.prompt, 'Neu');
  });

  test('a quiz with a changed question exports and imports unchanged', () {
    final changed = convertQuestion(
      kindOf<TrueFalseQuestion>(),
      kindOf<MultipleChoiceQuestion>(),
    ).question;
    final quiz = Quiz(
      id: 'quiz',
      name: 'Q',
      description: 'D',
      category: 'C',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: [changed],
    );
    expect(parseQuizImport(exportQuizJson(quiz)).questions, [changed]);
  });
}
