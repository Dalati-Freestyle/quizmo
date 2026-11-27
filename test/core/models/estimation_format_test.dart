import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/models/models.dart';

const time = EstimationValueFormat.minutesSeconds;
const hours = EstimationValueFormat.hoursMinutesSeconds;
const number = EstimationValueFormat.number;

EstimationQuestion question({double? target = 2038}) => EstimationQuestion(
  id: 'q',
  prompt: 'Wie lange dauert der Film?',
  correctValue: target,
  minAccepted: 1980,
  maxAccepted: 2100,
  valueFormat: time,
  timeLimit: Duration.zero,
);

EstimationAnswer answer(double value) => EstimationAnswer(
  playerId: 'p',
  questionId: 'q',
  clientTimestampMicros: 0,
  clockOffsetMicros: 0,
  value: value,
);

void main() {
  test('mm:ss reads and writes seconds', () {
    expect(time.parse('33:58'), 2038);
    expect(time.parse(' 33:00 '), 1980);
    expect(time.parse('35:00'), 2100);
    expect(time.parse('0:05'), 5);
    expect(time.parse('90:00'), 5400);
    expect(time.parse('1:02,5'), 62.5);
    expect(time.parse('-0:12'), -12);
    for (final invalid in [
      '33:75',
      'abc',
      '33',
      '33:5',
      '1:02:03',
      '',
      ':30',
    ]) {
      expect(time.parse(invalid), isNull, reason: invalid);
    }
    expect(time.format(2038), '33:58');
    expect(time.format(5), '0:05');
    expect(time.format(5400), '90:00');
    expect(time.format(62.5), '1:02.5');
    expect(time.format(59.9999), '1:00');
    expect(time.format(-12), '-0:12');
  });

  test('h:mm:ss reads and writes seconds', () {
    expect(hours.parse('1:02:03'), 3723);
    expect(hours.parse('0:59:59'), 3599);
    expect(hours.parse('1:60:00'), isNull);
    expect(hours.parse('62:03'), isNull);
    expect(hours.format(3723), '1:02:03');
    expect(hours.format(59), '0:00:59');
  });

  test('numbers stay as before', () {
    expect(number.parse('1,5'), 1.5);
    expect(number.parse('33:58'), isNull);
    expect(number.parse('inf'), isNull);
    expect(number.format(655), '655');
    expect(number.formatDeviation(-12), '-12');
  });

  test('deviations are signed', () {
    expect(time.formatDeviation(12), '+0:12');
    expect(time.formatDeviation(-65), '-1:05');
    expect(time.formatDeviation(0), '±0:00');
  });

  test('a time question scores, labels and redacts like a number', () {
    final q = question();
    expect(q.accuracy(answer(2050)), 1);
    expect(q.accuracy(answer(2200)), closeTo(1 - 162 / 2038, 1e-9));
    expect(q.solutionLabel, '33:58 (33:00 – 35:00)');
    expect(q.valueLabel(2050), '34:10');
    expect(q.deviationLabel(2050), '+0:12');
    final redacted = q.redacted();
    expect(redacted.valueFormat, time);
    expect(redacted.deviationLabel(2050), isNull);
    expect(Question.fromJson(q.toJson()), q);
    expect(
      const EstimationQuestion(id: 'q', prompt: 'x').toJson(),
      isNot(contains('valueFormat')),
    );
    expect(
      () => Question.fromJson({...q.toJson(), 'valueFormat': 'weeks'}),
      throwsA(isA<JsonContractException>()),
    );
  });

  test('schema 17 imports unchanged and may not use a time format', () {
    final source = File(
      p.join('test', 'fixtures', 'quiz_v17_with_media.quizmo.json'),
    ).readAsStringSync();
    final quiz = parseQuizImport(source);
    expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
    final estimation = quiz.questions.whereType<EstimationQuestion>().last;
    expect(estimation.valueFormat, number);
    expect(quiz.questions.whereType<LocationQuestion>(), hasLength(1));
    expect(quiz.questions.first.media, isNotEmpty);
    expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
    final json = jsonDecode(source) as JsonMap;
    ((json['questions'] as List).last as JsonMap)['valueFormat'] =
        'minutesSeconds';
    expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
    final current = Quiz.fromJson({...json, 'schemaVersion': 18});
    expect((current.questions.last as EstimationQuestion).valueFormat, time);
    expect(
      parseQuizImport(exportQuizJson(current)).questions,
      current.questions,
    );
  });
}
