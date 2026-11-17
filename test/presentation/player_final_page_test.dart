import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/player/player_final_page.dart';

const _protocol = GameProtocol(
  title: 'Quizabend',
  generatedAtMicros: 1700000000000000,
  format: ProtocolFormat.standard,
  teamMode: true,
  standings: [
    ProtocolStanding(
      id: 'red',
      name: 'Rot',
      isTeam: true,
      score: 30,
      place: 1,
      memberIds: ['p1'],
      memberNames: ['Anna'],
    ),
    ProtocolStanding(
      id: 'blue',
      name: 'Blau',
      isTeam: true,
      score: 30,
      place: 1,
      memberIds: ['p2'],
      memberNames: ['Ben'],
    ),
    ProtocolStanding(
      id: 'green',
      name: 'Grün',
      isTeam: true,
      score: 5,
      place: 3,
      memberIds: ['p3'],
      memberNames: ['Cem'],
    ),
  ],
  questions: [
    ProtocolQuestion(
      number: 1,
      questionId: 'q',
      prompt: 'Hauptstadt?',
      solution: 'Berlin',
      answers: [
        ProtocolAnswer(
          playerId: 'p3',
          player: 'Cem',
          team: 'Grün',
          answer: 'München',
          status: ProtocolAnswerStatus.incorrect,
        ),
      ],
    ),
  ],
  corrections: [
    ProtocolCorrection(
      atMicros: 1700000000000000,
      kind: ProtocolCorrectionKind.points,
      target: 'Grün',
      before: 0,
      after: 5,
      delta: 5,
      reason: 'Fair play 🤷',
    ),
  ],
);

void main() {
  Future<void> pump(WidgetTester tester, String playerId) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerFinalPage(
          game: const GameState(
            isFinished: true,
            mode: TeamMode(),
            protocol: _protocol,
          ),
          playerId: playerId,
        ),
      ),
    ),
  );

  testWidgets('shows standings with shared places and the own team', (
    tester,
  ) async {
    await pump(tester, 'p3');
    expect(find.text('Quiz beendet'), findsOneWidget);
    expect(find.text('1.'), findsNWidgets(2));
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('Grün (Dein Team)'), findsOneWidget);
    expect(
      find.text('Dein Team Grün belegt Platz 3 von 3 mit 5 Punkte.'),
      findsOneWidget,
    );
    expect(find.textContaining('nach dem Neuladen'), findsOneWidget);
  });

  testWidgets('opens the full protocol with answers and reasons', (
    tester,
  ) async {
    await pump(tester, 'p1');
    await tester.tap(find.byKey(const ValueKey('view-protocol')));
    await tester.pumpAndSettle();
    expect(find.text('Spielprotokoll'), findsOneWidget);
    expect(find.text('1. Hauptstadt?'), findsOneWidget);
    expect(find.text('Lösung: Berlin'), findsOneWidget);
    expect(find.textContaining('München'), findsOneWidget);
    expect(find.textContaining('Fair play 🤷'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
