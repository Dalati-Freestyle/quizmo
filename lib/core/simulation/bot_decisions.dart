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
  int variant = 0,
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

  // Without a stored solution (snowflake quiz) nothing is right or wrong:
  // the bot picks one of the possible answers by [variant].
  if (!question.hasSolution && question.supportsUniqueness) {
    final result = answer(_freeChoice(question, variant));
    if (!question.accepts(result)) {
      throw StateError('Cannot simulate a valid answer for ${question.id}.');
    }
    return result;
  }

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

Map<String, Object?> _freeChoice(Question question, int variant) {
  List<String> turned(List<String> values) => [
    ...values.skip(variant % values.length),
    ...values.take(variant % values.length),
  ];
  return switch (question) {
    MultipleChoiceQuestion(:final options) => {
      'kind': 'multipleChoice',
      'optionIds': [options[variant % options.length].id],
    },
    TrueFalseQuestion() => {'kind': 'trueFalse', 'value': variant.isEven},
    OrderingQuestion(:final items) => {
      'kind': 'ordering',
      'itemIds': turned([for (final item in items) item.id]),
    },
    MatchingQuestion(:final leftItems, :final rightItems) => {
      'kind': 'matching',
      'pairs': Map.fromIterables(
        leftItems.map((item) => item.id),
        turned([for (final item in rightItems) item.id]),
      ),
    },
    BuzzerQuestion() || ShortAnswerQuestion() || EstimationQuestion() =>
      throw StateError('Cannot pick a free answer for ${question.id}.'),
  };
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
  final simple = target != 0
      ? (target > 0 ? -target : 0.0)
      : question.zeroScale;
  final lower = question.minAccepted;
  final upper = question.maxAccepted;
  if (lower == null || upper == null || simple < lower || simple > upper) {
    return simple;
  }
  // Inside the tolerance: leave it upwards, far enough for zero credit.
  final distance = target != 0 ? target.abs() : question.zeroScale;
  return max(upper, target + distance) + distance;
}
