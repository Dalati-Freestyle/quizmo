import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

List<AnswerOption> options(int count, [String prefix = 'i']) => [
  for (var i = 0; i < count; i++) AnswerOption(id: '$prefix$i', label: '$i'),
];

void main() {
  test('the order is the same every time and per question', () {
    final items = options(6);
    expect(displayOrder(items, 'q1'), displayOrder(items, 'q1'));
    expect(displayOrder(items, 'q1').toSet(), items.toSet());
    // Another question gets another order (for these seeds).
    expect(displayOrder(items, 'q1'), isNot(displayOrder(items, 'q2')));
  });

  test('the platform independent generator gives fixed orders', () {
    // Fixed results guard against a generator that differs between the web
    // build and the VM (String.hashCode and Random may).
    expect(
      displayOrder(options(5), 'question-1').map((o) => o.id).toList(),
      displayOrder(options(5), 'question-1').map((o) => o.id).toList(),
    );
    expect(displayOrder([1, 2, 3, 4, 5, 6, 7, 8], 'abc'), _expectedAbc);
  });

  test('ordering: never the entered order, for any question', () {
    for (var n = 2; n <= 6; n++) {
      for (var q = 0; q < 200; q++) {
        final question = OrderingQuestion(
          id: 'q$q',
          prompt: '?',
          items: options(n),
          correctOrder: [for (final o in options(n)) o.id],
        );
        expect(question.displayItems, isNot(question.items));
        expect(question.displayItems.toSet(), question.items.toSet());
        // Guests (without the solution) see the same order as the host.
        expect(question.redacted().displayItems, question.displayItems);
      }
    }
  });

  test('matching: no right item stands beside its own left item', () {
    for (var n = 2; n <= 6; n++) {
      for (var q = 0; q < 200; q++) {
        final left = options(n, 'l');
        final right = options(n, 'r');
        final question = MatchingQuestion(
          id: 'q$q',
          prompt: '?',
          leftItems: left,
          rightItems: right,
          correctPairs: {for (var i = 0; i < n; i++) left[i].id: right[i].id},
        );
        final shownLeft = question.displayLeftItems;
        final shownRight = question.displayRightItems;
        final aligned = [
          for (final item in shownLeft) question.correctPairs![item.id],
        ];
        expect(shownRight.map((r) => r.id).toList(), isNot(aligned));
        expect(question.redacted().displayRightItems, shownRight);
        expect(question.redacted().displayLeftItems, shownLeft);
      }
    }
  });
}

const _expectedAbc = [2, 8, 6, 7, 4, 3, 5, 1];
