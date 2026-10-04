import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  Quiz quiz(int chips, {bool withTeams = true}) => Quiz(
    id: 'poker',
    name: 'Poker',
    description: 'Chips',
    category: 'Test',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    teams: withTeams ? const [Team(id: 'a', name: 'A')] : const [],
    format: PokerFormat(startingChips: chips),
  );

  test('quiz import and export preserve poker configuration', () {
    final original = quiz(250);
    expect(Quiz.fromJson(original.toJson()), original);
    expect(original.schemaVersion, 1);
  });
  test('invalid poker settings cannot be imported', () {
    for (final original in [
      quiz(0),
      quiz(-1),
      quiz(1000001),
      quiz(100, withTeams: false),
    ]) {
      expect(original.validationErrors(), isNotEmpty);
      expect(
        () => Quiz.fromJson(original.toJson()),
        throwsA(isA<QuizValidationException>()),
      );
    }
  });
  test('legacy quiz without format still imports as standard', () {
    final json = quiz(100).toJson()..remove('format');
    expect(Quiz.fromJson(json).format, const StandardFormat());
  });
}
