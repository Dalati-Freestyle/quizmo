import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/data/session_recovery.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';

const epoch = 1700000000000000;
const question = TrueFalseQuestion(
  id: 'q',
  prompt: 'Grüße, "Welt"\nNeue Zeile',
  correctAnswer: true,
  adminNotes: 'private host notes',
  scoringRule: FixedPointsRule(correctPoints: 10),
);
const teams = {
  'a': Team(id: 'a', name: 'Äpfel'),
  'b': Team(id: 'b', name: 'B'),
};

void main() {
  late QuizEngineBloc engine;
  late int now;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> join({bool teammate = false}) async {
    for (final player in [
      const Player(id: 'p1', name: '=HYPERLINK("bad")', teamId: 'a'),
      const Player(id: 'p2', name: 'Zoë', teamId: 'b'),
      if (teammate) const Player(id: 'p3', name: 'Mate', teamId: 'a'),
    ]) {
      engine.resumeTokenHashes[player.id] = hashResumeToken(
        'private-resume-${player.id}',
      );
      await send(
        PlayerJoinedEvent(
          engine.state.game.teams.containsKey(player.teamId)
              ? player
              : player.copyWith(teamId: null),
        ),
      );
    }
  }

  Future<void> answer(String id, bool value) => send(
    SubmitAnswerEvent(
      TrueFalseAnswer(
        playerId: id,
        questionId: 'q',
        clientTimestampMicros: now + 25000,
        clockOffsetMicros: 25000,
        value: value,
      ),
    ),
  );
  SessionReport report() =>
      SessionReport.fromGame(engine.state.game, title: 'Quiz, ü');

  setUp(() {
    now = epoch;
    engine = QuizEngineBloc(questionBank: const [question], now: () => now);
  });
  tearDown(() => engine.close());

  test(
    'solo final standings, missing input, disconnects, units and corrections',
    () async {
      await join();
      await send(const StartRoundEvent('q'));
      now += 1500000;
      await answer('p1', true);
      await send(const PlayerLeftEvent('p2'));
      await send(const RevealRoundEvent());
      await send(
        CorrectScoreEvent(
          requestId: 'fix',
          playerId: 'p1',
          questionId: 'q',
          roundStartedAt: epoch,
          delta: -3,
          reason: '+correction',
        ),
      );
      final result = report();
      expect(result.finished, isTrue);
      expect(result.historyComplete, isTrue);
      expect(result.summaries.first.finalScore, 7);
      expect(result.summaries.first.hitRate, 1);
      expect(result.summaries.first.meanElapsedMicros, 1500000);
      expect(result.answers.first.elapsedMicros, 1500000);
      expect(result.answers.last.status, ReportAnswerStatus.noAnswer);
      expect(result.answers.last.disconnected, isTrue);
      expect(result.summaries.last.hitRate, isNull);
      expect(result.progress.where((p) => p.id == 'p1').map((p) => p.score), [
        0,
        7,
      ]);
      expect(result.corrections.single['score_delta'], -3);
      await send(const UndoCorrectionEvent('score-fix'));
      expect(report().summaries.first.finalScore, 10);
      expect(report().progress.lastWhere((p) => p.id == 'p1').score, 10);
      expect(report().corrections.last['reverses_correction'], 'score-fix');
      final csv = report().toCsv();
      expect(csv, isNot(contains('private host notes')));
      expect(csv, isNot(contains('private-resume')));
      expect(engine.state.game.redactedForPlayers().reportRounds, isEmpty);
      expect(
        engine.state.game.redactedForPlayers().toJson()['reportRounds'],
        isEmpty,
      );
    },
  );

  test(
    'standard team mode sums member scores and judged submissions',
    () async {
      await engine.close();
      engine = QuizEngineBloc(
        questionBank: const [question],
        teams: teams,
        mode: const TeamMode(),
        now: () => now,
      );
      await join(teammate: true);
      await send(const StartRoundEvent('q'));
      await answer('p1', true);
      await answer('p3', false);
      await send(const RevealRoundEvent());
      final team = report().summaries.firstWhere(
        (s) => s.isTeam && s.id == 'a',
      );
      expect(team.finalScore, engine.state.game.teamScores['a']);
      expect(team.evaluated, 2);
      expect(team.hitRate, 0.5);
      final rows = csvRows(report().toCsv());
      final summary = rows.firstWhere(
        (r) => r['row_type'] == 'question_summary' && r['entity_id'] == 'a',
      );
      expect(summary['hit_rate_ratio'], '0.5');
      expect(summary['evaluated_answers'], '2');
    },
  );

  test(
    'partial estimation accuracy is not a full hit or a Poker payout',
    () async {
      await engine.close();
      const estimation = EstimationQuestion(
        id: 'q',
        prompt: 'Estimate',
        correctValue: 100,
      );
      engine = QuizEngineBloc(
        questionBank: const [estimation],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 100,
        now: () => now,
      );
      await join();
      await send(const StartRoundEvent('q'));
      await send(
        const PlacePokerWagerEvent(playerId: 'p1', questionId: 'q', wager: 20),
      );
      await send(const OpenPokerAnswersEvent());
      await send(
        SubmitAnswerEvent(
          EstimationAnswer(
            playerId: 'p1',
            questionId: 'q',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
            value: 150,
          ),
        ),
      );
      await send(const RevealRoundEvent());
      final result = report();
      expect(result.answers.first.accuracy, 0.5);
      expect(result.answers.first.status, ReportAnswerStatus.partial);
      expect(
        result.summaries.firstWhere((s) => s.isTeam && s.id == 'a').hitRate,
        0,
      );
      expect(
        result.summaries.firstWhere((s) => s.isTeam && s.id == 'a').finalScore,
        80,
      );
    },
  );

  test(
    'manual verdicts and corrections override automatic text matching',
    () async {
      await engine.close();
      const manual = ShortAnswerQuestion(
        id: 'q',
        prompt: 'Manual',
        acceptedAnswers: ['Different'],
        manualGrading: true,
      );
      engine = QuizEngineBloc(questionBank: const [manual], now: () => now);
      await join();
      await send(const StartRoundEvent('q'));
      await send(
        SubmitAnswerEvent(
          ShortAnswer(
            playerId: 'p1',
            questionId: 'q',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
            text: '\t=SUM(1,2)\n"Äpfel"',
          ),
        ),
      );
      expect(report().answers.first.accuracy, isNull);
      await send(
        const JudgeAnswerEvent(
          playerId: 'p1',
          questionId: 'q',
          startedAtHostMicros: epoch,
          wasCorrect: false,
        ),
      );
      await send(
        const JudgeAnswerEvent(
          playerId: 'p1',
          questionId: 'q',
          startedAtHostMicros: epoch,
          wasCorrect: true,
        ),
      );
      await send(const RevealRoundEvent());
      expect(report().answers.first.accuracy, 1);
      expect(report().summaries.first.hitRate, 1);
      final row = csvRows(report().toCsv())
          .firstWhere((r) => r['row_type'] == 'answer');
      expect(row['answer'], '\'\t=SUM(1,2)\n"Äpfel"');
    },
  );

  test('choice, ordering and matching retain IDs and duplicate labels', () {
    const options = [
      AnswerOption(id: 'a', label: 'Same'),
      AnswerOption(id: 'b', label: 'Same'),
    ];
    final choice = jsonDecode(
      reportAnswerLabel(
        const MultipleChoiceAnswer(
          playerId: 'p',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          optionIds: ['a', 'b'],
        ),
        const MultipleChoiceQuestion(id: 'q', prompt: 'Q', options: options),
      ),
    ) as List;
    expect(choice.map((dynamic o) => o['id']), ['a', 'b']);
    final ordering = jsonDecode(
      reportAnswerLabel(
        const OrderingAnswer(
          playerId: 'p',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          itemIds: ['b', 'a'],
        ),
        const OrderingQuestion(id: 'q', prompt: 'Q', items: options),
      ),
    ) as List;
    expect(ordering.map((dynamic o) => o['id']), ['b', 'a']);
    final matching = jsonDecode(
      reportAnswerLabel(
        const MatchingAnswer(
          playerId: 'p',
          questionId: 'q',
          clientTimestampMicros: 0,
          clockOffsetMicros: 0,
          pairs: {'a': 'a', 'b': 'b'},
        ),
        const MatchingQuestion(
          id: 'q',
          prompt: 'Q',
          leftItems: options,
          rightItems: options,
        ),
      ),
    ) as List;
    expect(matching.length, 2);
    expect(matching.map((dynamic o) => o['left_id']), ['a', 'b']);
  });

  for (final daily in [false, true]) {
    test(
      'Jeopardy keeps initial and steal phases, dailyDouble=$daily',
      () async {
        await engine.close();
        engine = QuizEngineBloc(
          questionBank: const [question],
          mode: const TeamMode(),
          teams: teams,
          now: () => now,
          jeopardyBoard: JeopardyBoard(
            categories: [
              JeopardyCategory(
                name: 'C',
                cells: [JeopardyCell(questionId: 'q', isDailyDouble: daily)],
              ),
            ],
            rowPoints: const [100],
            allowSteal: true,
            penalizeWrongAnswers: true,
          ),
        );
        await join();
        await send(const StartGameEvent());
        await send(const SelectJeopardyCellEvent('q'));
        if (daily) await send(const PlaceDailyDoubleWagerEvent(75));
        await answer('p1', false);
        if (!daily) {
          expect(engine.state.game.reportRounds.length, 2);
          now += 1000000;
          await answer('p2', true);
        }
        if (!engine.state.game.isFinished) await send(const RevealRoundEvent());
        final result = report();
        expect(result.format, 'jeopardy');
        expect(result.answers.first.pointsAtStake, daily ? 75 : 100);
        expect(result.answers.first.accuracy, 0);
        expect(result.answers[1].status, ReportAnswerStatus.notEligible);
        if (daily) {
          expect(result.answers.every((a) => a.dailyDouble), isTrue);
          expect(result.answers.any((a) => a.steal), isFalse);
          expect(
            result.summaries
                .firstWhere((s) => s.isTeam && s.id == 'a')
                .finalScore,
            -75,
          );
        } else {
          expect(
            result.answers
                .where((a) => a.steal && a.playerId == 'p2')
                .single
                .accuracy,
            1,
          );
          expect(
            result.answers
                .where((a) => a.steal && a.playerId == 'p2')
                .single
                .elapsedMicros,
            1000000,
          );
          expect(
            result.summaries
                .firstWhere((s) => s.isTeam && s.id == 'a')
                .finalScore,
            -100,
          );
          expect(
            result.summaries
                .firstWhere((s) => s.isTeam && s.id == 'b')
                .finalScore,
            100,
          );
        }
        expect(
          result.summaries
              .where((s) => s.isTeam)
              .map((s) => s.finalScore)
              .toSet(),
          engine.state.game.teamScores.values.toSet(),
        );
        if (!daily) {
          final before = result.answers
              .map((a) => (a.phase, a.playerId, a.accuracy, a.elapsedMicros))
              .toList();
          final finished = engine.state.game;
          await engine.close();
          now += 9000000;
          engine = QuizEngineBloc(
            restoredGame: finished.copyWith(recoveryPaused: true),
            questionBank: const [question],
            now: () => now,
          );
          await send(
            const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
          );
          expect(
            report().answers.map(
              (a) => (a.phase, a.playerId, a.accuracy, a.elapsedMicros),
            ),
            before,
          );
          expect(engine.state.game.reportRounds.length, 2);
        }
      },
    );
  }

  test(
    'undoing a Jeopardy buzzer miss removes the dependent steal phase',
    () async {
      await engine.close();
      const buzz = BuzzerQuestion(
        id: 'q',
        prompt: 'Buzz',
        expectedAnswer: 'Spoken',
      );
      engine = QuizEngineBloc(
        questionBank: const [buzz],
        mode: const TeamMode(),
        teams: teams,
        now: () => now,
        autoContinueBuzzer: false,
        jeopardyBoard: const JeopardyBoard(
          categories: [
            JeopardyCategory(
              name: 'C',
              cells: [JeopardyCell(questionId: 'q')],
            ),
          ],
          rowPoints: [100],
          allowSteal: true,
          penalizeWrongAnswers: true,
        ),
      );
      await join();
      await send(const StartGameEvent());
      await send(const SelectJeopardyCellEvent('q'));
      await send(
        BuzzerPressEvent(
          BuzzerPress(
            playerId: 'p1',
            questionId: 'q',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
          ),
        ),
      );
      await send(const LockBuzzerEvent());
      await send(const JudgeBuzzerEvent(wasCorrect: false));
      expect(report().answers.any((a) => a.steal), isTrue);
      await send(const UndoCorrectionEvent('judgment-1'));
      expect(report().answers.any((a) => a.steal), isFalse);
      expect(report().answers.first.accuracy, isNull);
      expect(engine.state.game.reportRounds.length, 1);
      expect(
        report().summaries
            .firstWhere((s) => s.isTeam && s.id == 'a')
            .finalScore,
        0,
      );
      await send(const JudgeBuzzerEvent(wasCorrect: true));
      await send(const RevealRoundEvent());
      expect(report().answers.first.accuracy, 1);
      expect(
        report().summaries
            .firstWhere((s) => s.isTeam && s.id == 'a')
            .finalScore,
        100,
      );
    },
  );

  test(
    'completed answers survive removal without inventing a final score',
    () async {
      await join();
      await send(const StartRoundEvent('q'));
      await answer('p1', true);
      await send(const RevealRoundEvent());
      await send(const KickPlayerEvent('p1'));
      final result = report();
      final removed = result.summaries.firstWhere((s) => s.id == 'p1');
      expect(removed.inRoster, isFalse);
      expect(removed.finalScore, isNull);
      expect(removed.hitRate, 1);
      expect(result.answers.first.accuracy, 1);
      expect(
        csvRows(result.toCsv()).firstWhere(
          (r) => r['row_type'] == 'summary' && r['entity_id'] == 'p1',
        )['connection'],
        'removed_from_roster',
      );
    },
  );

  test('CSV version 1 fixes the exact column order', () {
    expect(SessionReport.columns, [
      'report_version',
      'row_type',
      'quiz',
      'format',
      'finished',
      'history_complete',
      'phase',
      'question_id',
      'question',
      'entity_type',
      'entity_id',
      'name',
      'team_id',
      'team',
      'answer',
      'status',
      'accuracy_ratio',
      'response_time_ms',
      'response_time_kind',
      'connection',
      'practice_only',
      'wager_chips',
      'points_at_stake',
      'steal',
      'daily_double',
      'score_unit',
      'score',
      'evaluated_answers',
      'fully_correct_answers',
      'hit_rate_ratio',
      'mean_response_time_ms',
      'correction_id',
      'reason',
      'value_before',
      'value_after',
      'reverses_correction',
      'score_delta',
    ]);
  });

  test(
    'Poker records stakes, chips, practice, teammates and explicit skipping',
    () async {
      await engine.close();
      const second = TrueFalseQuestion(
        id: 'q2',
        prompt: 'Second',
        correctAnswer: true,
      );
      engine = QuizEngineBloc(
        questionBank: const [question, second],
        mode: const TeamMode(),
        teams: teams,
        pokerStartingChips: 100,
        now: () => now,
      );
      await join(teammate: true);
      await send(const StartRoundEvent('q'));
      await send(
        const PlacePokerWagerEvent(playerId: 'p1', questionId: 'q', wager: 100),
      );
      now += 5000000; // Betting is not answer time and must not add a phase.
      await send(const OpenPokerAnswersEvent());
      now += 1000000;
      await answer('p1', false);
      await send(const RevealRoundEvent());
      var result = report();
      expect(
        result.answers.where((a) => a.playerId == 'p1').single.elapsedMicros,
        1000000,
      );
      expect(result.answers.where((a) => a.playerId == 'p1').single.wager, 100);
      expect(
        result.answers.where((a) => a.playerId == 'p3').single.status,
        ReportAnswerStatus.teamAnswered,
      );
      expect(
        result.answers.where((a) => a.playerId == 'p2').single.status,
        ReportAnswerStatus.notEligible,
      );
      expect(engine.state.game.reportRounds.length, 1);
      await send(const NextQuestionEvent());
      await send(const OpenPokerAnswersEvent());
      await send(
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: 'p1',
            questionId: 'q2',
            clientTimestampMicros: now,
            clockOffsetMicros: 0,
            value: true,
          ),
        ),
      );
      await send(const RevealRoundEvent());
      await send(
        CorrectScoreEvent(
          playerId: 'p1',
          questionId: 'q2',
          roundStartedAt: now,
          requestId: 'chips',
          delta: 5,
        ),
      );
      result = report();
      expect(
        result.answers.lastWhere((a) => a.playerId == 'p1').practice,
        isTrue,
      );
      expect(
        result.summaries
            .where((s) => !s.isTeam)
            .every((s) => s.finalScore == null),
        isTrue,
      );
      expect(
        result.summaries.firstWhere((s) => s.isTeam && s.id == 'a').finalScore,
        5,
      );
      expect(
        result.progress
            .where((p) => p.id == 'a' && p.isTeam)
            .map((p) => p.score),
        [100, 0, 5],
      );
      expect(result.progress.any((p) => !p.isTeam), isFalse);
    },
  );

  test('buzzer verdict and elapsed survive queue clearing and undo', () async {
    await engine.close();
    const buzz = BuzzerQuestion(
      id: 'q',
      prompt: 'Buzz',
      expectedAnswer: 'Spoken',
    );
    engine = QuizEngineBloc(
      questionBank: const [buzz],
      now: () => now,
      autoContinueBuzzer: false,
    );
    await join();
    await send(const StartRoundEvent('q'));
    now += 250000;
    await send(
      BuzzerPressEvent(
        BuzzerPress(
          playerId: 'p1',
          questionId: 'q',
          clientTimestampMicros: now,
          clockOffsetMicros: 0,
        ),
      ),
    );
    await send(const LockBuzzerEvent());
    await send(const JudgeBuzzerEvent(wasCorrect: false));
    expect(engine.state.game.round.buzzerQueue, isEmpty);
    expect(report().answers.first.accuracy, 0);
    expect(report().answers.first.elapsedMicros, 250000);
    expect(
      report().answers.first.answer,
      contains('spoken answer not recorded'),
    );
    await send(const UndoCorrectionEvent('judgment-1'));
    expect(report().answers.first.status, ReportAnswerStatus.ungraded);
    await send(const JudgeBuzzerEvent(wasCorrect: true));
    await send(const RevealRoundEvent());
    expect(report().answers.first.accuracy, 1);
  });

  test('recovery round trip retains report, avoids duplicate active phases and resets it', () async {
    await join();
    await send(const StartRoundEvent('q'));
    now += 1000000;
    await answer('p1', true);
    final quiz = Quiz(
      id: 'quiz',
      name: 'Report',
      description: 'Report test',
      category: 'Tests',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [question],
    );
    final saved = SessionCheckpoint(
      sessionId: 'report-session-12345678',
      quiz: quiz,
      game: engine.state.game,
      savedAtMicros: now,
      resumeTokenHashes: engine.resumeTokenHashes,
    );
    final decoded = SessionCheckpoint.decode(
      saved.encode(),
      quizDocument: jsonEncode(quiz.toJson()),
    );
    expect(decoded.game.reportRounds, engine.state.game.reportRounds);
    expect(jsonDecode(saved.encode())['schemaVersion'], 4);
    final legacyPayload = jsonDecode(
      jsonDecode(saved.encode())['payload'] as String,
    ) as Map<String, dynamic>;
    (legacyPayload['game'] as Map<String, dynamic>).remove('reportRounds');
    final payload = jsonEncode(legacyPayload);
    final legacyEnvelope = {
      'schemaVersion': 3,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    };
    final migrated = SessionCheckpoint.decode(
      jsonEncode(legacyEnvelope),
      quizDocument: jsonEncode(quiz.toJson()),
    );
    expect(migrated.game.reportRounds, isEmpty);
    expect(jsonDecode(migrated.encode())['schemaVersion'], 4);
    expect(
      () => SessionCheckpoint.decode(
        jsonEncode({...legacyEnvelope, 'schemaVersion': 4}),
        quizDocument: jsonEncode(quiz.toJson()),
      ),
      throwsA(isA<RecoveryException>()),
    );
    await engine.close();
    now += 9000000;
    engine = QuizEngineBloc(
      questionBank: quiz.questions,
      restoredGame: decoded.pausedGame(),
      now: () => now,
    );
    await send(const ResumeRecoveredGameEvent(RecoveryTimerPolicy.restart));
    await send(const RevealRoundEvent());
    expect(engine.state.game.reportRounds.length, 1);
    expect(report().answers.first.elapsedMicros, 1000000);
    expect(report().summaries.first.finalScore, 10);
    await send(const ResetGameEvent());
    expect(engine.state.game.reportRounds, isEmpty);
  });

  test(
    'older snapshots show unavailable detail instead of reconstructing metrics',
    () {
      final result = SessionReport.fromGame(
        const GameState(
          isFinished: true,
          completedQuestionIds: {'q'},
          players: {'p1': Player(id: 'p1', name: 'P')},
          scores: ScoreState(byPlayer: {'p1': 42}),
        ),
        title: 'Old save',
      );
      expect(result.historyComplete, isFalse);
      expect(result.summaries.single.finalScore, 42);
      expect(result.summaries.single.hitRate, isNull);
      expect(result.answers, isEmpty);
    },
  );

  test(
    'CSV has fixed columns, UTF-8 BOM, escaped delimiters and multiline data',
    () async {
      await join();
      await send(const StartRoundEvent('q'));
      await answer('p1', true);
      await send(const RevealRoundEvent());
      final csv = report().toCsv();
      expect(utf8.decode(utf8.encode(csv)), csv.substring(1));
      expect(utf8.encode(csv).take(3), [239, 187, 191]);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv.endsWith('\r\n'), isTrue);
      final rows = csvRows(csv);
      expect(
        rows.every((r) => r.length == SessionReport.columns.length),
        isTrue,
      );
      expect(rows.first['quiz'], 'Quiz, ü');
      expect(rows.first['name'], '\'=HYPERLINK("bad")');
      final detail = rows.firstWhere((r) => r['row_type'] == 'answer');
      expect(detail['question'], question.prompt);
      expect(detail['response_time_ms'], '0.0');
      expect(detail['wager_chips'], 'N/A');
      expect(detail['status'], 'correct');
      expect(csv, contains('Grüße, ""Welt""\nNeue Zeile'));
    },
  );

  test('spreadsheet formula protection covers whitespace and preserves signed numbers', () {
    for (final text in [
      '=1+1',
      '+cmd',
      '-2+3',
      '@SUM(1)',
      '  =1',
      '\t@bad',
      '\r=bad',
      '\n+bad',
      '＝1',
      '\u0000=bad',
    ]) {
      expect(csvCell(text), startsWith('"\''));
    }
    expect(csvCell(-12), '"-12"');
    expect(csvCell('Äpfel, "gut"\nJa'), '"Äpfel, ""gut""\nJa"');
  });
}

List<Map<String, String>> csvRows(String csv) {
  final records = <List<String>>[];
  var fields = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 1; i < csv.length; i++) {
    final char = csv[i];
    if (char == '"') {
      if (quoted && i + 1 < csv.length && csv[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      fields.add(field.toString());
      field = StringBuffer();
    } else if (char == '\r' && !quoted) {
      expect(csv[++i], '\n');
      fields.add(field.toString());
      records.add(fields);
      fields = [];
      field = StringBuffer();
    } else {
      field.write(char);
    }
  }
  expect(quoted, isFalse);
  return [
    for (final row in records.skip(1))
      {for (var i = 0; i < records.first.length; i++) records.first[i]: row[i]},
  ];
}
