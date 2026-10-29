import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';
import 'package:quizmo/core/simulation/preview_session.dart';

import 'bot_decisions_test.dart' show simulationQuestions;

Quiz simulationQuiz({
  List<Question>? questions,
  QuizFormat format = const StandardFormat(),
}) => Quiz(
  id: 'preview-source',
  name: 'Draft',
  description: 'Unsaved content',
  category: 'Tests',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: questions ?? simulationQuestions,
  format: format,
);

Future<void> open(PreviewSession session, String id) async {
  session.send(const StartGameEvent());
  session.send(StartRoundEvent(id));
  await session.flush();
}

void main() {
  test('closing during queued engine work leaves no timers', () async {
    final session = PreviewSession(simulationQuiz());
    session.addParticipant(name: 'Bot', bot: BotSettings());
    session.send(const StartRoundEvent('bool'));
    await session.close();
    expect(session.clock.pendingCount, 0);
    expect(session.engine.isClosed, isTrue);
  });

  test(
    'guest snapshots are cached until an actual engine transition',
    () async {
      final session = PreviewSession(simulationQuiz());
      addTearDown(session.close);
      final initial = session.guestGame;
      await session.advance(const Duration(seconds: 1));
      expect(identical(initial, session.guestGame), isTrue);
      session.addParticipant(name: 'Manual');
      await session.flush();
      expect(identical(initial, session.guestGame), isFalse);
    },
  );

  test('snapshot cloning includes draft without mutating its lists', () async {
    final questions = simulationQuestions.toList();
    final quiz = simulationQuiz(questions: questions);
    final session = PreviewSession(quiz);
    addTearDown(session.close);
    questions.clear();
    expect(session.quiz.questions, simulationQuestions);
    expect(session.engine.recoverySessionId, isNull);
    expect(session.engine.persistRecovery, isNull);
    expect(session.guestGame.questionBank, isEmpty);
    session.addParticipant(name: 'Manual');
    await open(session, 'bool');
    expect(session.guestGame.round.question!.hasSolution, isFalse);
    expect(session.engine.state.currentQuestion!.hasSolution, isTrue);
    expect(quiz.teams, isEmpty);
  });

  test(
    'guest redaction preserves visible uploads, never solution media or notes',
    () async {
      final source = Quiz.fromJson(
        jsonDecode(
          File(
            p.join('test', 'fixtures', 'quiz_v1_with_media.quizmo.json'),
          ).readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final session = PreviewSession(source);
      addTearDown(session.close);
      session.addParticipant(name: 'Manual');
      final question = source.questions.firstWhere(
        (q) => q.solutionMedia.isNotEmpty,
      );
      await open(session, question.id);
      final guest = session.guestGame.round.question!;
      expect(guest.solutionMedia, isEmpty);
      expect(guest.adminNotes, isEmpty);
      expect(guest.hasSolution, isFalse);
      expect(guest.media.first.asset!.data, isNotNull);
      expect(
        session.engine.state.game
            .redactedForPlayers()
            .round
            .question!
            .media
            .first
            .asset!
            .data,
        isNull,
      );
      session.send(const EndRoundEvent());
      await session.flush();
      expect(
        session.guestGame.round.question!.solutionMedia.first.asset!.data,
        isNotNull,
      );
    },
  );

  for (final question in simulationQuestions) {
    for (final correct in [false, true]) {
      test('bot ${correct ? "right" : "wrong"} on ${question.id}', () async {
        final session = PreviewSession(simulationQuiz(questions: [question]));
        addTearDown(session.close);
        final id = session.addParticipant(
          name: 'Bot',
          bot: BotSettings(
            accuracy: correct ? 1 : 0,
            minDelayMs: 10,
            maxDelayMs: 10,
          ),
        );
        await open(session, question.id);
        await session.advance(const Duration(seconds: 1));
        final round = session.engine.state.game.round;
        if (question is BuzzerQuestion) {
          expect(round.buzzerVerdicts[id], correct ? 1 : 0);
        } else {
          expect(round.answers, contains(id));
          expect(question.accuracy(round.answers[id]!), correct ? 1 : 0);
        }
      });
    }
  }

  test('manual text bots are judged before host finalizes', () async {
    final question = ShortAnswerQuestion(
      id: 'manual',
      prompt: 'Manual',
      acceptedAnswers: ['Solution'],
      manualGrading: true,
    );
    final session = PreviewSession(simulationQuiz(questions: [question]));
    addTearDown(session.close);
    final id = session.addParticipant(
      name: 'Bot',
      bot: BotSettings(accuracy: 1, minDelayMs: 1, maxDelayMs: 1),
    );
    await open(session, question.id);
    await session.advance(const Duration(seconds: 1));
    expect(session.engine.state.game.round.answerVerdicts[id], 1);
    expect(session.engine.state.game.round.pendingGradeCount, 0);
    session.send(const RevealRoundEvent());
    await session.flush();
    expect(session.engine.state.game.completedQuestionIds, {question.id});
  });

  test(
    'delay boundary, round end, removal and close cancel pending actions',
    () async {
      final session = PreviewSession(simulationQuiz());
      final id = session.addParticipant(
        name: 'Bot',
        bot: BotSettings(minDelayMs: 100, maxDelayMs: 100),
      );
      session.addParticipant(name: 'Manual');
      await open(session, 'bool');
      await session.advance(const Duration(milliseconds: 99));
      expect(session.engine.state.game.round.answers, isEmpty);
      await session.advance(const Duration(milliseconds: 1));
      expect(session.engine.state.game.round.answers, contains(id));
      session.send(const EndRoundEvent());
      session.send(const CloseRoundEvent());
      session.send(const StartRoundEvent('choice'));
      await session.flush();
      session.removeParticipant(id);
      await session.advance(const Duration(seconds: 1));
      expect(session.engine.state.game.round.answers, isEmpty);
      expect(
        session.trace
            .where((entry) => entry.action.startsWith('answer:'))
            .length,
        1,
      );
      await session.close();
      expect(session.clock.pendingCount, 0);
      expect(() => session.send(const NextQuestionEvent()), throwsStateError);
    },
  );

  test('expired rounds never receive delayed answers', () async {
    final question = TrueFalseQuestion(
      id: 'q',
      prompt: 'Q',
      correctAnswer: true,
      timeLimit: const Duration(milliseconds: 50),
    );
    final session = PreviewSession(simulationQuiz(questions: [question]));
    addTearDown(session.close);
    session.addParticipant(
      name: 'Late',
      bot: BotSettings(accuracy: 1, minDelayMs: 100, maxDelayMs: 100),
    );
    await open(session, question.id);
    await session.advance(const Duration(seconds: 1));
    expect(session.engine.state.roundStatus, RoundStatus.locked);
    expect(session.engine.state.game.round.answers, isEmpty);
    expect(session.trace, isEmpty);
  });

  test(
    'same seed and inputs yield identical decisions and exact timelines',
    () async {
      Future<({String game, String trace})> scenario() async {
        final session = PreviewSession(simulationQuiz(), seed: 54321);
        for (var i = 0; i < 6; i++) {
          session.addParticipant(
            name: 'Bot $i',
            bot: BotSettings(accuracy: 0.53, minDelayMs: 0, maxDelayMs: 700),
          );
        }
        await open(session, 'choice');
        await session.advance(const Duration(seconds: 1));
        session.send(const NextQuestionEvent());
        await session.advance(const Duration(seconds: 1));
        final result = (
          game: jsonEncode(session.engine.state.game.toJson()),
          trace: session.trace.toString(),
        );
        await session.close();
        return result;
      }

      expect(await scenario(), await scenario());
    },
  );

  test('pausing bots cancels actions without pausing engine expiry', () async {
    final session = PreviewSession(simulationQuiz());
    addTearDown(session.close);
    session.addParticipant(
      name: 'Bot',
      bot: BotSettings(minDelayMs: 20, maxDelayMs: 20),
    );
    await open(session, 'bool');
    session.setBotsEnabled(false);
    await session.advance(const Duration(milliseconds: 100));
    expect(session.engine.state.game.round.answers, isEmpty);
    session.setBotsEnabled(true);
    await session.advance(const Duration(milliseconds: 20));
    expect(session.engine.state.game.round.answers.length, 1);
  });

  test(
    'replay restores pre-question scores and answers in a new engine',
    () async {
      final session = PreviewSession(simulationQuiz());
      session.addParticipant(
        name: 'Bot',
        bot: BotSettings(accuracy: 1, minDelayMs: 10, maxDelayMs: 10),
      );
      await open(session, 'bool');
      await session.advance(const Duration(seconds: 1));
      expect(
        session.engine.state.game.scores.byPlayer.values.single,
        greaterThan(0),
      );
      final replay = session.replayRound();
      await session.close();
      addTearDown(replay.close);
      await replay.flush();
      expect(replay.engine.state.game.scores.byPlayer.values.single, 0);
      expect(replay.engine.state.game.round.answers, isEmpty);
      await replay.advance(const Duration(seconds: 1));
      expect(
        replay.engine.state.game.scores.byPlayer.values.single,
        greaterThan(0),
      );
    },
  );

  test(
    'poker bots reserve legal stakes, wait for host, then settle once per team',
    () async {
      final session = PreviewSession(
        simulationQuiz(format: const PokerFormat(startingChips: 100)),
      );
      addTearDown(session.close);
      final first = session.addParticipant(
        name: 'Team bot',
        bot: BotSettings(accuracy: 1, minDelayMs: 10, maxDelayMs: 10),
      );
      await session.flush();
      final team = session.engine.state.game.players[first]!.teamId!;
      session.addParticipant(
        name: 'Team mate',
        teamId: team,
        bot: BotSettings(accuracy: 0, minDelayMs: 20, maxDelayMs: 20),
      );
      await open(session, 'bool');
      await session.advance(const Duration(seconds: 1));
      final wager = session.engine.state.game.poker!.wagers[team]!;
      expect(wager, inInclusiveRange(1, 100));
      expect(session.engine.state.game.round.answers, isEmpty);
      session.send(const OpenPokerAnswersEvent());
      await session.advance(const Duration(seconds: 1));
      expect(session.engine.state.game.round.answers.length, 1);
      expect(session.engine.state.game.poker!.chips[team], 100 + wager);
      final replay = session.replayRound();
      addTearDown(replay.close);
      await replay.flush();
      expect(replay.engine.state.game.poker!.chips[team], 100);
      expect(replay.engine.state.game.poker!.wagers, isEmpty);
      expect(replay.engine.state.game.poker!.betting, isTrue);
    },
  );

  test('Jeopardy bots choose legally, await confirmation and place bounded Daily Double', () async {
    const board = JeopardyBoard(
      categories: [
        JeopardyCategory(
          name: 'Category',
          cells: [JeopardyCell(questionId: 'bool', isDailyDouble: true)],
        ),
      ],
      rowPoints: [200],
    );
    final session = PreviewSession(
      simulationQuiz(
        questions: [simulationQuestions.firstWhere((q) => q.id == 'bool')],
        format: const JeopardyFormat(board),
      ),
    );
    addTearDown(session.close);
    final id = session.addParticipant(
      name: 'Picker',
      bot: BotSettings(accuracy: 1, minDelayMs: 10, maxDelayMs: 10),
    );
    session.send(const StartGameEvent());
    await session.advance(const Duration(seconds: 1));
    expect(session.engine.state.game.jeopardy!.pendingPickQuestionId, 'bool');
    expect(session.engine.state.game.round.question, isNull);
    session.send(
      ConfirmQuestionPickEvent(
        questionId: 'bool',
        playerId: id,
        accepted: true,
      ),
    );
    await session.advance(const Duration(milliseconds: 10));
    final jeopardy = session.engine.state.game.jeopardy!;
    expect(jeopardy.activePoints, inInclusiveRange(1, 200));
    await session.advance(const Duration(seconds: 1));
    expect(session.engine.state.game.completedQuestionIds, {'bool'});
  });

  test('deferred results stay secret until the quiz is finished', () async {
    final session = PreviewSession(
      simulationQuiz(
        questions: [
          ...simulationQuestions.whereType<TrueFalseQuestion>(),
          ...simulationQuestions.whereType<OrderingQuestion>(),
        ],
        format: const StandardFormat(revealMode: SolutionRevealMode.atEnd),
      ),
    );
    addTearDown(session.close);
    session.addParticipant(
      name: 'Bot',
      bot: BotSettings(accuracy: 1, minDelayMs: 0, maxDelayMs: 0),
    );
    await open(session, 'bool');
    expect(session.guestGame.resultsHidden, isTrue);
    expect(session.guestGame.scores.byPlayer, isEmpty);
    expect(session.guestGame.round.question!.hasSolution, isFalse);
    session.send(const NextQuestionEvent());
    await session.flush();
    expect(session.guestGame.showFinalReview, isTrue);
    expect(session.guestGame.roundHistory.length, 2);
    expect(
      session.guestGame.roundHistory.every(
        (round) => round.question!.hasSolution,
      ),
      isTrue,
    );
  });
}
