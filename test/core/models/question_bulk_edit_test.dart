import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  final picture = ImageAttachment(
    asset: MediaAsset.upload(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]),
      'png',
    ),
    caption: 'Eiffel Tower',
  );
  final choice = MultipleChoiceQuestion(
    id: 'mc',
    prompt: 'Pick b',
    category: 'Old',
    timeLimit: const Duration(seconds: 10),
    options: const [
      AnswerOption(id: 'a', label: 'A'),
      AnswerOption(id: 'b', label: 'B'),
    ],
    correctOptionId: 'b',
    media: [picture],
    solutionMedia: [picture],
    adminNotes: 'Keep me',
  );
  const text = ShortAnswerQuestion(
    id: 'text',
    prompt: 'Capital?',
    acceptedAnswers: ['Paris'],
  );
  const buzz = BuzzerQuestion(id: 'buzz', prompt: 'Buzz', expectedAnswer: 'X');

  test('an empty edit changes nothing', () {
    const edit = QuestionBulkEdit();
    expect(edit.isEmpty, isTrue);
    for (final question in [choice, text, buzz]) {
      expect(edit.apply(question), question);
    }
  });

  test('changes only the framing, never the question itself', () {
    const edit = QuestionBulkEdit(
      timeLimit: Duration(seconds: 60),
      softTimeLimit: true,
      category: ' Geografie ',
      scoringRule: FixedPointsRule(correctPoints: 5, wrongPoints: -1),
      hideQuestionMediaDetails: true,
      imageZoom: false,
    );
    final edited = edit.apply(choice) as MultipleChoiceQuestion;
    expect(edited.timeLimit, const Duration(seconds: 60));
    expect(edited.softTimeLimit, isTrue);
    expect(edited.category, 'Geografie');
    expect(
      edited.scoringRule,
      const FixedPointsRule(correctPoints: 5, wrongPoints: -1),
    );
    expect(edited.media.single.hideDetails, isTrue);
    expect((edited.media.single as ImageAttachment).zoom, isFalse);
    // Solution media keep their details, everything else stays.
    expect(edited.solutionMedia.single.hideDetails, isFalse);
    expect(edited.prompt, choice.prompt);
    expect(edited.options, choice.options);
    expect(edited.correctOptionId, 'b');
    expect(edited.adminNotes, 'Keep me');
    expect(edited.id, choice.id);
  });

  test('no time limit also means no soft limit', () {
    const edit = QuestionBulkEdit(
      timeLimit: Duration.zero,
      softTimeLimit: true,
    );
    final edited = edit.apply(choice);
    expect(edited.hasTimeLimit, isFalse);
    expect(edited.softTimeLimit, isFalse);
  });

  test('an empty category removes it', () {
    expect(const QuestionBulkEdit(category: '').apply(choice).category, isNull);
  });

  test('kind specific settings only reach the kinds that have them', () {
    const edit = QuestionBulkEdit(
      manualGrading: true,
      maxEdits: 3,
      lockOutOnMiss: false,
      hostEndsRound: true,
    );
    final editedText = edit.apply(text) as ShortAnswerQuestion;
    expect(editedText.manualGrading, isTrue);
    expect(editedText.maxEdits, 3);
    final editedBuzz = edit.apply(buzz) as BuzzerQuestion;
    expect(editedBuzz.lockOutOnMiss, isFalse);
    expect(editedBuzz.hostEndsRound, isTrue);
    expect(edit.apply(choice), choice);
  });
}
