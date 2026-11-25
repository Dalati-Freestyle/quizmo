import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/preview_session.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/player/player_page.dart';
import 'package:quizmo/presentation/player/player_session_cubit.dart';
import 'package:quizmo/presentation/player/questions/new_question_views.dart';

import '../core/simulation/preview_session_test.dart' show simulationQuiz;

const _text = ShortAnswerQuestion(
  id: 'text',
  prompt: 'Capital?',
  acceptedAnswers: ['Berlin'],
  timeLimit: Duration.zero,
);
const _choice = TrueFalseQuestion(
  id: 'bool',
  prompt: 'True?',
  correctAnswer: true,
  timeLimit: Duration.zero,
);

void main() {
  late PreviewSession session;
  late PlayerSessionCubit player;
  late String me;
  late String mate;

  Future<void> open(WidgetTester tester, Question question) async {
    session = PreviewSession(
      simulationQuiz(questions: [question]).copyWith(
        teams: const [
          Team(id: 'a', name: 'A'),
          Team(id: 'b', name: 'B'),
        ],
      ),
    );
    addTearDown(session.close);
    me = session.addParticipant(name: 'Ada', teamId: 'a');
    mate = session.addParticipant(name: 'Linus', teamId: 'a');
    session.addParticipant(name: 'Other', teamId: 'b');
    session.send(const StartGameEvent());
    await tester.runAsync(session.flush);
    player = PlayerSessionCubit.local(
      playerId: me,
      initialGame: session.guestGame,
      snapshots: session.guestSnapshots,
      send: session.send,
      now: () => session.clock.nowMicros,
      answers: () => playerAnswersOf(session.engine.state.game, me),
    );
    addTearDown(player.close);
    session.send(StartRoundEvent(question.id));
    await tester.runAsync(session.flush);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: BlocProvider.value(
            value: player,
            child: const LocalPlayerBoard(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => session.advance(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  Future<void> mateAnswers(WidgetTester tester, AnswerSubmission answer) async {
    session.send(SubmitAnswerEvent(answer));
    await settle(tester);
  }

  ShortAnswer text(String value) => ShortAnswer(
    playerId: mate,
    questionId: 'text',
    clientTimestampMicros: session.clock.nowMicros,
    clockOffsetMicros: 0,
    text: value,
  );

  testWidgets('a team mate replaces the answer, the own input stays', (
    tester,
  ) async {
    await open(tester, _text);
    await tester.enterText(find.byType(TextField), 'Bonn');
    await tester.pump();
    await tester.tap(find.text('Antwort senden'));
    await settle(tester);
    expect(find.textContaining('Gültige Teamantwort: Bonn'), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-sent')), findsOneWidget);

    await mateAnswers(tester, text('Berlin'));
    expect(
      find.text('Gültige Teamantwort: Berlin (von Linus)'),
      findsOneWidget,
    );
    expect(find.text('Linus hat die Teamantwort geändert.'), findsOneWidget);
    expect(find.text('Bonn'), findsOneWidget, reason: 'own input untouched');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.text('Antwort ersetzen'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('resend-own-answer')));
    await tester.tap(find.byKey(const ValueKey('resend-own-answer')));
    await settle(tester);
    expect(find.textContaining('Gültige Teamantwort: Bonn'), findsOneWidget);
    expect(player.state.submissionStatus, SubmissionStatus.accepted);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('input that was not sent counts when the answers close', (
    tester,
  ) async {
    await open(tester, _text);
    await tester.enterText(find.byType(TextField), 'Berlin');
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    session.send(const RevealRoundEvent());
    await settle(tester);
    expect(player.state.roundStatus, RoundStatus.locked);
    await tester.runAsync(
      () => session.advance(QuizEngineBloc.defaultDraftGrace),
    );
    await tester.pump();
    expect(player.state.roundStatus, RoundStatus.revealed);
    expect(
      find.text('Zeit abgelaufen: Deine Eingabe wurde übernommen.'),
      findsOneWidget,
    );
    expect(session.engine.state.game.teamScores['a'], greaterThan(0));
  });

  testWidgets('a press on the other option replaces the team answer', (
    tester,
  ) async {
    await open(tester, _choice);
    await tester.tap(find.byKey(const ValueKey('true-false-true')));
    await settle(tester);
    expect(find.text('Wahr · Teamantwort'), findsOneWidget);
    await mateAnswers(
      tester,
      TrueFalseAnswer(
        playerId: mate,
        questionId: 'bool',
        clientTimestampMicros: session.clock.nowMicros,
        clockOffsetMicros: 0,
        value: false,
      ),
    );
    expect(find.text('Falsch · Teamantwort'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('true-false-true')));
    await settle(tester);
    expect(find.text('Wahr · Teamantwort'), findsOneWidget);
    expect(find.byType(TrueFalseQuestionView), findsOneWidget);
  });
}
