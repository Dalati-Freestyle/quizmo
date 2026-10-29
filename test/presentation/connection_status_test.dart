import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/connection_status_view.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/questions/multiple_choice_question_view.dart';
import 'package:quizmo/presentation/player/submission_status_view.dart';
import 'package:quizmo/presentation/quizmaster/dashboard_panels.dart';

import '../helpers/mock_lan_discovery.dart';

const question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Pick one',
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
);

void main() {
  setUp(mockLanDiscoveryUnavailable);
  testWidgets(
    'a stopped host shows no live connections without changing the saved roster',
    (tester) async {
      const game = GameState(
        players: {'p': Player(id: 'p', name: 'Ada')},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayersPanel(
              game: game,
              connectionsAvailable: false,
              onAssignTeam: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('Players (0 online)'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(game.players['p']!.isConnected, isTrue);
    },
  );

  testWidgets(
    'all connection states have readable text and live announcements',
    (tester) async {
      for (final (status, label) in [
        (QuizClientStatus.connecting, 'Connecting to the host...'),
        (QuizClientStatus.connected, 'Connected to the host'),
        (
          QuizClientStatus.reconnecting,
          'Connection interrupted. Reconnecting to the room...',
        ),
        (QuizClientStatus.closed, 'Connection ended'),
        (QuizClientStatus.disconnected, 'Not connected'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConnectionStatusView(status: status)),
          ),
        );
        expect(find.text(label), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('only authoritative acceptance is shown as success', (
    tester,
  ) async {
    for (final (submission, status, label) in [
      (
        SubmissionStatus.sending,
        QuizClientStatus.connected,
        'Sending. Waiting for host confirmation...',
      ),
      (
        SubmissionStatus.uncertain,
        QuizClientStatus.reconnecting,
        'Confirmation missing. Your answer may not have arrived.',
      ),
      (
        SubmissionStatus.rejected,
        QuizClientStatus.connected,
        'No submission accepted. Answer again if the round is still open.',
      ),
      (
        SubmissionStatus.accepted,
        QuizClientStatus.connected,
        'The host accepted your submission.',
      ),
      (
        SubmissionStatus.accepted,
        QuizClientStatus.reconnecting,
        'Last confirmed: the host accepted your submission.',
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubmissionStatusView(
              state: PlayerSessionState(
                status: status,
                playerId: 'p',
                submissionStatus: submission,
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      if (submission != SubmissionStatus.accepted) {
        expect(find.text('The host accepted your submission.'), findsNothing);
        expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      }
    }
  });

  testWidgets(
    'multiple choice does not claim acceptance locally and unlocks after reconciliation',
    (tester) async {
      final submissions = <String>[];
      Future<void> show(String? selected) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultipleChoiceQuestionView(
              question: question,
              status: RoundStatus.acceptingAnswers,
              selectedOptionId: selected,
              onSelect: submissions.add,
            ),
          ),
        ),
      );
      await show(null);
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(
        find.text('Sending. Waiting for host confirmation...'),
        findsOneWidget,
      );
      expect(find.text('The host accepted your submission.'), findsNothing);
      await show('a');
      await show(null);
      await tester.tap(find.text('B'));
      expect(submissions, ['a', 'b']);
    },
  );

  testWidgets('a disconnected player keeps the last board but cannot submit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    await tester.pumpAndSettle();
    final session = tester
        .element(find.byType(Scaffold))
        .read<PlayerSessionCubit>();
    final game = GameState(
      players: const {'p': Player(id: 'p', name: 'Ada')},
      round: const RoundState(
        question: question,
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: 1,
      ),
    );
    session.emit(
      PlayerSessionState(
        status: QuizClientStatus.reconnecting,
        playerId: 'p',
        game: game,
        submissionStatus: SubmissionStatus.uncertain,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MultipleChoiceQuestionView), findsOneWidget);
    expect(find.text('Join a session'), findsNothing);
    final input = tester.widget<MultipleChoiceQuestionView>(
      find.byType(MultipleChoiceQuestionView),
    );
    expect(input.enabled, isFalse);
    expect(
      find.text('Confirmation missing. Your answer may not have arrived.'),
      findsOneWidget,
    );
    session.emit(session.state.copyWith(status: QuizClientStatus.closed));
    await tester.pumpAndSettle();
    expect(find.text('Connection ended'), findsOneWidget);
  });
}
