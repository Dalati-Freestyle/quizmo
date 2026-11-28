import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_result_view.dart';

const question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Wo liegt Jakarta?',
  options: [
    AnswerOption(id: 'option-1', label: 'Thailand'),
    AnswerOption(id: 'option-2', label: 'Malaysia'),
    AnswerOption(id: 'option-3', label: 'Indonesien'),
  ],
  correctOptionIds: ['option-3'],
);

MultipleChoiceAnswer choose(List<String> ids) => MultipleChoiceAnswer(
  playerId: 'p',
  questionId: 'q',
  clientTimestampMicros: 1,
  clockOffsetMicros: 0,
  optionId: ids.first,
  optionIds: ids.length > 1 ? ids : null,
);

void main() {
  test('host views show the letter and text of the chosen option', () {
    expect(answerLabel(choose(['option-3']), question), 'C · Indonesien');
    expect(
      answerLabel(choose(['option-1', 'option-3']), question),
      'A · Thailand, C · Indonesien',
    );
    expect(
      answerLabel(choose(['option-3']), question),
      isNot(contains('option-')),
    );
    // An option that no longer exists falls back to its ID.
    expect(answerLabel(choose(['gone']), question), 'gone');
  });
}
