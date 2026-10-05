/// Renders the Jeopardy phases of the TV canvas and the shared board widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/common/jeopardy_board_view.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

void main() {
  final joinUri = Uri.parse('http://192.168.1.42:8080');

  const board = JeopardyBoard(
    rowPoints: [100, 200],
    categories: [
      JeopardyCategory(
        name: 'Science',
        cells: [
          JeopardyCell(questionId: 'q1'),
          JeopardyCell(questionId: 'q2', isDailyDouble: true),
        ],
      ),
      JeopardyCategory(
        name: 'History',
        cells: [
          JeopardyCell(questionId: 'q3'),
          JeopardyCell.empty,
        ],
      ),
    ],
  );

  const teams = {
    'red': Team(id: 'red', name: 'Red Foxes'),
    'blue': Team(id: 'blue', name: 'Blue Whales'),
  };

  Future<void> pump(WidgetTester tester, GameState game) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuizmoApp.buildTheme(Brightness.dark),
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: game,
              snapshotReceivedAt: DateTime.now(),
            ),
            joinUri: joinUri,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('shows the board, the categories and whose turn it is', (
    tester,
  ) async {
    await pump(
      tester,
      GameState(
        mode: const TeamMode(),
        teams: teams,
        jeopardy: JeopardyState.start(board, teams.keys),
      ),
    );

    expect(find.text('Science'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('100'), findsNWidgets(2));
    expect(find.text('Red Foxes picks the next question'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces a Daily Double that waits for its wager', (
    tester,
  ) async {
    await pump(
      tester,
      GameState(
        mode: const TeamMode(),
        teams: teams,
        jeopardy: JeopardyState.start(
          board,
          teams.keys,
        ).copyWith(pendingDailyDoubleId: 'q2'),
      ),
    );

    expect(find.text('DAILY DOUBLE'), findsOneWidget);
    expect(find.textContaining('place your wager'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board cells report taps and keep played points disabled', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: JeopardyBoardView(
              board: board,
              completedQuestionIds: const {'q1'},
              winners: const {'q1': 'Red Foxes'},
              onSelect: (id) => tapped = id,
            ),
          ),
        ),
      ),
    );

    // Played cells keep their value and cannot be selected again.
    expect(find.text('100'), findsNWidgets(2));
    expect(find.text('Red Foxes'), findsOneWidget);
    await tester.tap(find.text('100').first);
    expect(tapped, isNull);
    await tester.tap(find.text('100').last);
    expect(tapped, 'q3');
  });

  testWidgets('Daily Doubles stay hidden unless explicitly shown', (
    tester,
  ) async {
    Future<void> render({required bool show}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: JeopardyBoardView(
              board: board,
              completedQuestionIds: const {},
              showDailyDoubles: show,
            ),
          ),
        ),
      ),
    );

    await render(show: false);
    expect(find.byIcon(Icons.star), findsNothing);

    await render(show: true);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
