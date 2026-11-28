import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

Quiz quiz({List<InfoSlide> slides = const []}) => Quiz(
  id: 'cats',
  name: 'Kategorien',
  description: 'Fragen nach Kategorien',
  category: 'Test',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: const [
    TrueFalseQuestion(
      id: 'q1',
      prompt: 'A?',
      correctAnswer: true,
      category: 'Geschichte',
    ),
    TrueFalseQuestion(
      id: 'q2',
      prompt: 'B?',
      correctAnswer: true,
      category: 'geschichte ',
    ),
    TrueFalseQuestion(
      id: 'q3',
      prompt: 'C?',
      correctAnswer: true,
      category: 'Biologie',
    ),
  ],
  slides: slides,
);

void main() {
  test('a category slide survives export and import (schema 19)', () {
    final original = quiz(
      slides: const [
        InfoSlide(id: 's', title: 'Geschichte', category: 'Geschichte'),
      ],
    );
    expect(Quiz.currentSchemaVersion, 19);
    final json = original.toJson();
    expect(json['schemaVersion'], 19);
    final restored = Quiz.fromJson(json);
    expect(restored, original);
    expect(restored.slides.single.category, 'Geschichte');
  });

  test('schema 18 files import unchanged, without category slides', () {
    final json = {
      ...quiz(
        slides: const [InfoSlide(id: 's', title: 'Pause')],
      ).toJson(),
      'schemaVersion': 18,
    };
    final imported = Quiz.fromJson(json);
    expect(imported.schemaVersion, Quiz.currentSchemaVersion);
    expect(imported.slides.single.category, isNull);
    expect(imported.questions, hasLength(3));
  });

  test('a schema 18 file cannot carry a category slide', () {
    final json = {
      ...quiz(
        slides: const [InfoSlide(id: 's', title: 'G', category: 'Geschichte')],
      ).toJson(),
      'schemaVersion': 18,
    };
    expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
  });

  test('one slide per category', () {
    final twice = quiz(
      slides: const [
        InfoSlide(id: 'a', title: 'G', category: 'Geschichte'),
        InfoSlide(id: 'b', title: 'G2', category: ' geschichte'),
      ],
    );
    expect(
      twice.validationErrors(),
      contains('Jede Kategorie kann nur eine Kategorie-Folie haben.'),
    );
  });

  test('categories and the warning for partly missing slides', () {
    expect(quiz().categories, ['Geschichte', 'Biologie']);
    // No category slide at all: no warning.
    expect(quiz().hasPartialCategorySlides, isFalse);
    final partial = quiz(
      slides: const [InfoSlide(id: 's', title: 'G', category: 'Geschichte')],
    );
    expect(partial.hasPartialCategorySlides, isTrue);
    final coverage = partial.categorySlideCoverage;
    expect((coverage.covered, coverage.uncovered), (2, 1));
    expect(coverage.missing, ['Biologie']);
    // Every question has its slide: the warning disappears.
    final complete = quiz(
      slides: const [
        InfoSlide(id: 's', title: 'G', category: 'Geschichte'),
        InfoSlide(id: 't', title: 'B', category: 'Biologie'),
      ],
    );
    expect(complete.hasPartialCategorySlides, isFalse);
  });
}
