import 'dart:math';

import '../models/models.dart';

final class BotSettings {
  BotSettings({
    this.accuracy = 0.7,
    this.minDelayMs = 300,
    this.maxDelayMs = 1800,
  }) {
    if (!accuracy.isFinite || accuracy < 0 || accuracy > 1) {
      throw ArgumentError.value(accuracy, 'accuracy');
    }
    if (minDelayMs < 0 || maxDelayMs < minDelayMs || maxDelayMs > 3600000) {
      throw ArgumentError('Invalid bot delay range (0..3600000 ms).');
    }
  }

  final double accuracy;
  final int minDelayMs;
  final int maxDelayMs;

  Duration delay(Random random) => Duration(
    milliseconds: minDelayMs + random.nextInt(maxDelayMs - minDelayMs + 1),
  );

  bool succeeds(Random random) => random.nextDouble() < accuracy;
}

AnswerSubmission botAnswer(
  Question question, {
  required String playerId,
  required int timestamp,
  required bool correct,
}) {
  AnswerSubmission answer(Map<String, Object?> payload) =>
      AnswerSubmission.fromJson({
        ...payload,
        'playerId': playerId,
        'questionId': question.id,
        'clientTimestampMicros': timestamp,
        // Local participants share the virtual host clock: exact offset zero.
        'clockOffsetMicros': 0,
      });

  final payload = switch (question) {
    MultipleChoiceQuestion() => {
      'kind': 'multipleChoice',
      'optionIds': _choice(question, correct),
    },
    BuzzerQuestion() => {'kind': 'buzzer'},
    ShortAnswerQuestion() => {
      'kind': 'shortAnswer',
      'text': correct ? question.acceptedAnswers!.first : _wrongText(question),
    },
    OrderingQuestion() => {
      'kind': 'ordering',
      'itemIds': correct
          ? question.correctOrder!
          : _rotate(question.correctOrder!),
    },
    MatchingQuestion() => {
      'kind': 'matching',
      'pairs': correct
          ? question.correctPairs!
          : Map.fromIterables(
              question.correctPairs!.keys,
              _rotate(question.correctPairs!.values.toList()),
            ),
    },
    EstimationQuestion() => {
      'kind': 'estimation',
      'value': correct ? question.correctValue! : _wrongEstimate(question),
    },
    TrueFalseQuestion() => {
      'kind': 'trueFalse',
      'value': correct ? question.correctAnswer! : !question.correctAnswer!,
    },
  };
  final result = answer(payload);
  if (!question.accepts(result) ||
      (question is! BuzzerQuestion &&
          question.accuracy(result) != (correct ? 1 : 0))) {
    throw StateError('Cannot simulate a valid answer for ${question.id}.');
  }
  return result;
}

List<String> _choice(MultipleChoiceQuestion question, bool correct) {
  if (correct) return question.solutionOptionIds;
  final wrong = question.options
      .where((option) => !question.solutionOptionIds.contains(option.id))
      .firstOrNull;
  if (wrong != null) return [wrong.id];
  // When every option is correct, a strict subset is still a valid wrong answer.
  return [question.solutionOptionIds.first];
}

List<String> _rotate(List<String> values) => [...values.skip(1), values.first];

String _wrongText(ShortAnswerQuestion question) {
  var text = 'x';
  while (question.accuracy(
        ShortAnswer(
          playerId: '',
          questionId: question.id,
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          text: text,
        ),
      ) !=
      0) {
    text += 'x';
  }
  return text;
}

double _wrongEstimate(EstimationQuestion question) {
  final target = question.correctValue!;
  if (target != 0) return target > 0 ? -target : 0;
  return question.zeroScale;
}
