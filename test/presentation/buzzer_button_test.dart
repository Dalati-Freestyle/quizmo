/// Widget tests for the latency critical buzzer control.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/common/buzzer_button.dart';

void main() {
  Future<void> pumpBuzzer(
    WidgetTester tester, {
    required VoidCallback onPressed,
    BuzzerMode mode = BuzzerMode.ready,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: BuzzerButton(mode: mode, onPressed: onPressed),
          ),
        ),
      ),
    ),
  );

  testWidgets('fires on pointer down, before the pointer is lifted', (
    tester,
  ) async {
    var presses = 0;
    await pumpBuzzer(tester, onPressed: () => presses++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BuzzerButton)),
    );

    // No pointer-up yet: `GestureDetector.onTap` would still be waiting for
    // the gesture arena, the buzzer has already registered the press.
    expect(presses, 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(presses, 1);
  });

  testWidgets('survives a pointer cancel without a second press', (
    tester,
  ) async {
    var presses = 0;
    await pumpBuzzer(tester, onPressed: () => presses++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BuzzerButton)),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(presses, 1);
  });

  testWidgets('ignores presses while locked or already submitted', (
    tester,
  ) async {
    var presses = 0;
    for (final mode in [
      BuzzerMode.locked,
      BuzzerMode.submitted,
      BuzzerMode.won,
    ]) {
      await pumpBuzzer(tester, mode: mode, onPressed: () => presses++);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BuzzerButton)),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    expect(presses, 0);
  });

  testWidgets('keeps working inside a scrollable ancestor', (tester) async {
    // A gesture based button would lose the arena to the scrollable on a
    // slight finger movement; the raw pointer listener does not.
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 400),
              SizedBox(
                height: 240,
                child: BuzzerButton(onPressed: () => presses++),
              ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BuzzerButton)),
      kind: PointerDeviceKind.touch,
    );
    expect(presses, 1);

    await gesture.moveBy(const Offset(0, -40));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(presses, 1);
  });
}

