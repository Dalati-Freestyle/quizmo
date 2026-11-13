import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

Map<String, Object?> _file({
  required int schemaVersion,
  required List<Map<String, Object?>> teams,
}) => {
  'schemaVersion': schemaVersion,
  'id': 'colours',
  'name': 'Colours',
  'description': 'Team colours',
  'category': 'Test',
  'questions': [
    {
      'type': 'trueFalse',
      'id': 'q',
      'prompt': 'Q?',
      'timeLimitMs': 10000,
      'softTimeLimit': false,
      'category': null,
      'adminNotes': '',
      'media': [],
      'solutionMedia': [],
      'scoringRule': {'type': 'fixed', 'correctPoints': 10, 'wrongPoints': 0},
      'correctAnswer': true,
    },
  ],
  'teams': teams,
  'format': {'type': 'standard', 'revealMode': 'afterEachQuestion'},
  'createdAtMicros': 0,
  'updatedAtMicros': 0,
};

void main() {
  test('schema 9 is the current schema', () {
    expect(Quiz.currentSchemaVersion, 9);
  });

  test('the palette matches the admin view and has unique names', () {
    expect(TeamColor.values, hasLength(16));
    expect(TeamColor.values.map((c) => c.argb).toSet(), hasLength(16));
    for (final color in TeamColor.values) {
      expect(TeamColor.byName(color.name), color);
      expect(TeamColor.nearest(color.argb), color);
    }
    expect(TeamColor.byName('#FF0000'), isNull);
    expect(TeamColor.forIndex(16), TeamColor.values.first);
  });

  test('schema 8 colour codes move to the nearest palette colour', () {
    final quiz = parseQuizImport(
      jsonEncode(
        _file(
          schemaVersion: 8,
          teams: [
            {'id': 'a', 'name': 'A', 'colorValue': 0xFFE53935},
            {'id': 'b', 'name': 'B', 'colorValue': 0xFF3E63DD},
          ],
        ),
      ),
    );
    expect(quiz.schemaVersion, 9);
    expect(quiz.teams.first.colorValue, TeamColor.red.argb);
    expect(quiz.teams.last.colorValue, TeamColor.blue.argb);
  });

  test('schema 9 stores colour names and round-trips', () {
    final quiz = parseQuizImport(
      jsonEncode(
        _file(
          schemaVersion: 9,
          teams: [
            {'id': 'a', 'name': 'A', 'color': 'darkTeal'},
          ],
        ),
      ),
    );
    expect(quiz.teams.single.colorValue, TeamColor.darkTeal.argb);
    final exported = jsonDecode(exportQuizJson(quiz)) as Map<String, Object?>;
    expect((exported['teams']! as List).single, {
      'id': 'a',
      'name': 'A',
      'color': 'darkTeal',
    });
    expect(parseQuizImport(jsonEncode(exported)), quiz);
  });

  test('schema 9 rejects colour codes and unknown names', () {
    for (final team in [
      {'id': 'a', 'name': 'A', 'color': 'FFE53935'},
      {'id': 'a', 'name': 'A', 'colorValue': 0xFFE53935},
    ]) {
      expect(
        () =>
            parseQuizImport(jsonEncode(_file(schemaVersion: 9, teams: [team]))),
        throwsA(isA<QuizImportException>()),
      );
    }
  });

  test('teams created while joining get palette colours', () {
    final colors = {
      for (var index = 0; index < 3; index++) TeamColor.forIndex(index).argb,
    };
    expect(colors, hasLength(3));
  });
}
