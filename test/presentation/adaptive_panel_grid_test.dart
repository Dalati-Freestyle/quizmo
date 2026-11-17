import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/common/adaptive_layout.dart';

void main() {
  Future<void> pumpGrid(WidgetTester tester, {int? widePanelIndex}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptivePanelGrid(
            widePanelIndex: widePanelIndex,
            panels: [
              for (final name in ['details', 'teams', 'board'])
                SizedBox(key: ValueKey(name), height: 100),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('wide panel takes the double width middle column', (
    tester,
  ) async {
    await pumpGrid(tester, widePanelIndex: 2);

    final details = tester.getRect(find.byKey(const ValueKey('details')));
    final teams = tester.getRect(find.byKey(const ValueKey('teams')));
    final board = tester.getRect(find.byKey(const ValueKey('board')));

    expect(details.left, lessThan(board.left));
    expect(board.right, lessThan(teams.left));
    expect(board.width, closeTo(details.width * 2, 1));
    expect(teams.width, closeTo(details.width, 1));
  });

  testWidgets('without a wide panel the columns stay equal and in order', (
    tester,
  ) async {
    await pumpGrid(tester);

    final details = tester.getRect(find.byKey(const ValueKey('details')));
    final teams = tester.getRect(find.byKey(const ValueKey('teams')));
    final board = tester.getRect(find.byKey(const ValueKey('board')));

    expect(details.left, lessThan(teams.left));
    expect(teams.left, lessThan(board.left));
    expect(board.width, closeTo(details.width, 1));
  });
}
