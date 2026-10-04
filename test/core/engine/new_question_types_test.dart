import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/answer_evaluation.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  test('fuzzy matching normalizes whitespace/case and bounds edits', () {
    expect(fuzzyEquals('  BERLIN ', 'Berlin', 0), isTrue);
    expect(fuzzyEquals('Berln', 'Berlin', 1), isTrue);
    expect(fuzzyEquals('Bonn', 'Berlin', 1), isFalse);
    expect(fuzzyEquals('', 'a', 1), isFalse);
    expect(fuzzyEquals('😀', '😁', 1), isTrue);
  });
  test('estimation uses relative error and a finite scale at zero', () {
    expect(estimationAccuracy(90, 100, 1), closeTo(.9, .001));
    expect(estimationAccuracy(-90, -100, 1), closeTo(.9, .001));
    expect(estimationAccuracy(2, 0, 10), .8);
    expect(estimationAccuracy(300, 100, 1), 0);
  });
  const items = [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ];
  const ordering = OrderingQuestion(
    id: 'o',
    prompt: 'Order',
    items: items,
    correctOrder: ['b', 'a'],
  );
  const matching = MatchingQuestion(
    id: 'm',
    prompt: 'Match',
    leftItems: items,
    rightItems: items,
    correctPairs: {'a': 'b', 'b': 'a'},
  );
  test('ordering/matching reject duplicates, missing and unknown IDs', () {
    OrderingAnswer order(List<String> ids) => OrderingAnswer(
      playerId: 'p',
      questionId: 'o',
      clientTimestampMicros: 100,
      clockOffsetMicros: 20,
      itemIds: ids,
    );
    MatchingAnswer match(Map<String, String> pairs) => MatchingAnswer(
      playerId: 'p',
      questionId: 'm',
      clientTimestampMicros: 100,
      clockOffsetMicros: 20,
      pairs: pairs,
    );
    expect(ordering.accepts(order(['a', 'a'])), isFalse);
    expect(ordering.accepts(order(['a'])), isFalse);
    expect(ordering.accuracy(order(['b', 'a'])), 1);
    expect(matching.accepts(match({'a': 'b', 'b': 'b'})), isFalse);
    expect(matching.accepts(match({'a': 'x', 'b': 'a'})), isFalse);
    expect(matching.accuracy(match({'a': 'b', 'b': 'a'})), 1);
    expect(
      AnswerSubmission.fromJson(order(['b', 'a']).toJson()).hostTimestampMicros,
      80,
    );
  });
  test('all new questions round-trip and redact solutions', () {
    for (final question in <Question>[
      const ShortAnswerQuestion(
        id: 's',
        prompt: 'Text',
        acceptedAnswers: ['Berlin'],
      ),
      ordering,
      matching,
      const EstimationQuestion(id: 'e', prompt: 'Estimate', correctValue: 100),
      const TrueFalseQuestion(id: 't', prompt: 'True?', correctAnswer: false),
    ]) {
      expect(Question.fromJson(question.toJson()), question);
      expect(
        Question.fromJson(question.redacted().toJson()).hasSolution,
        isFalse,
      );
    }
  });
  test(
    'engine scores estimation proportionally, accepts only first answer',
    () async {
      const q = EstimationQuestion(
        id: 'e',
        prompt: 'Estimate',
        correctValue: 100,
      );
      final engine = QuizEngineBloc(questionBank: [q], now: () => 1000000);
      addTearDown(engine.close);
      engine.add(const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
      engine.add(const PlayerJoinedEvent(Player(id: 'other', name: 'Other')));
      engine.add(const StartRoundEvent('e'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.add(
        const SubmitAnswerEvent(
          EstimationAnswer(
            playerId: 'p',
            questionId: 'e',
            clientTimestampMicros: 1100000,
            clockOffsetMicros: 0,
            value: 90,
          ),
        ),
      );
      engine.add(
        const SubmitAnswerEvent(
          EstimationAnswer(
            playerId: 'p',
            questionId: 'e',
            clientTimestampMicros: 1100000,
            clockOffsetMicros: 0,
            value: 100,
          ),
        ),
      );
      engine.add(const RevealRoundEvent());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.state.game.scores.scoreOf('p'), 9);
    },
  );
}
