/// Renders the TV canvas for the interesting session phases.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

void main() {
  final joinUri = Uri.parse('http://192.168.1.42:8080');

  const choice = MultipleChoiceQuestion(
    id: 'q1',
    prompt: 'What is the capital of Australia?',
    category: 'Geography',
    options: [
      AnswerOption(id: 'a', label: 'Sydney'),
      AnswerOption(id: 'b', label: 'Canberra'),
      AnswerOption(id: 'c', label: 'Melbourne'),
      AnswerOption(id: 'd', label: 'Perth'),
    ],
  );

  Future<void> pump(WidgetTester tester, SpectatorSessionState state) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuizmoApp.buildTheme(Brightness.dark),
        home: Scaffold(
          body: TvScreen(state: state, joinUri: joinUri),
        ),
      ),
    );
    // Let the AnimatedSwitcher settle.
    await tester.pump(const Duration(seconds: 1));
  }

  const players = {
    'a': Player(id: 'a', name: 'Ada'),
    'b': Player(id: 'b', name: 'Linus'),
  };

  testWidgets('shows a connecting screen before the first snapshot', (
    tester,
  ) async {
    await pump(
      tester,
      const SpectatorSessionState(status: QuizClientStatus.connecting),
    );

    expect(find.text('Connecting to the quiz…'), findsOneWidget);
    expect(find.text('CONNECTING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the join address and roster in the lobby', (tester) async {
    await pump(
      tester,
      SpectatorSessionState(
        status: QuizClientStatus.connected,
        game: const GameState(players: players),
        snapshotReceivedAt: DateTime(2030),
      ),
    );

    expect(find.text('192.168.1.42:8080'), findsOneWidget);
    expect(find.text('2 players online'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the question without any solution while open', (
    tester,
  ) async {
    await pump(
      tester,
      SpectatorSessionState(
        status: QuizClientStatus.connected,
        snapshotReceivedAt: DateTime.now(),
        game: GameState(
          players: players,
          round: const RoundState(
            question: choice,
            status: RoundStatus.acceptingAnswers,
            startedAtHostMicros: 0,
          ),
        ),
      ),
    );
    // Stop the countdown ticker before the test ends.
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    expect(find.text('What is the capital of Australia?'), findsOneWidget);
    expect(find.text('Canberra'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('0 of 2 answered'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('highlights the solution and the awarded points on reveal', (
    tester,
  ) async {
    const solved = MultipleChoiceQuestion(
      id: 'q1',
      prompt: 'What is the capital of Australia?',
      options: [
        AnswerOption(id: 'a', label: 'Sydney'),
        AnswerOption(id: 'b', label: 'Canberra'),
      ],
      correctOptionId: 'b',
    );

    await pump(
      tester,
      SpectatorSessionState(
        status: QuizClientStatus.connected,
        snapshotReceivedAt: DateTime.now(),
        game: const GameState(
          players: players,
          scores: ScoreState(
            byPlayer: {'a': 12, 'b': 0},
            history: [
              ScoreEvent(
                playerId: 'a',
                questionId: 'q1',
                points: 12,
                reason: 'correct',
                atHostMicros: 1,
              ),
            ],
          ),
          round: RoundState(question: solved, status: RoundStatus.revealed),
        ),
      ),
    );

    expect(find.text('SOLUTION'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('+12  Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flags a lost connection but keeps the last known state', (
    tester,
  ) async {
    await pump(
      tester,
      SpectatorSessionState(
        status: QuizClientStatus.disconnected,
        reconnectAttempt: 1,
        game: const GameState(players: players),
        snapshotReceivedAt: DateTime(2030),
      ),
    );

    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.text('2 players online'), findsOneWidget);
  });
}

