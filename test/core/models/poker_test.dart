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
    expect(original.schemaVersion, Quiz.currentSchemaVersion);
  });
  test('invalid poker settings cannot be imported', () {
    for (final original in [quiz(0), quiz(-1), quiz(1000001)]) {
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
  test('poker lobby can start without predefined teams', () {
    final original = quiz(100, withTeams: false);
    expect(original.validationErrors(), isEmpty);
    expect(Quiz.fromJson(original.toJson()), original);
  });

  test('all stakes are in once every team that can bet placed one', () {
    const betting = PokerState(
      startingChips: 10,
      chips: {'a': 10, 'b': 10, 'broke': 0},
      betting: true,
    );
    const teams = ['a', 'b', 'broke'];
    expect(betting.allStakesIn(teams), isFalse);
    final one = betting.copyWith(
      chips: {'a': 7, 'b': 10, 'broke': 0},
      wagers: {'a': 3},
    );
    expect(one.allStakesIn(teams), isFalse);
    // Sitting out (0) is a placed stake; bankrupt teams are not waited for.
    final all = one.copyWith(wagers: {'a': 3, 'b': 0});
    expect(all.allStakesIn(teams), isTrue);
    // A withdrawn stake hides the notice again.
    expect(all.copyWith(wagers: {'b': 0}).allStakesIn(teams), isFalse);
    // Nobody can bet: nothing to announce.
    expect(
      const PokerState(
        startingChips: 10,
        chips: {'broke': 0},
      ).allStakesIn(['broke']),
      isFalse,
    );
  });
}
