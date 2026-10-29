import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/data/session_recovery.dart';
import 'package:quizmo/core/data/session_recovery_store_io.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/scoring_rules.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';

import '../../helpers/memory_recovery_store.dart';

const epoch = 1700000000000000;
const sessionId = 'recovery-session-123456789';
const question = TrueFalseQuestion(
  id: 'q',
  prompt: 'True?',
  correctAnswer: true,
  timeLimit: Duration(seconds: 10),
  scoringRule: SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10),
);
const buzzer = BuzzerQuestion(
  id: 'buzz',
  prompt: 'Buzz',
  expectedAnswer: 'Secret',
);
const teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};
const board = JeopardyBoard(
  categories: [
    JeopardyCategory(
      name: 'Any kind',
      cells: [
        JeopardyCell(questionId: 'q'),
        JeopardyCell(questionId: 'buzz', isDailyDouble: true),
      ],
    ),
  ],
  rowPoints: [100, 200],
  allowSteal: true,
);

Quiz quizFor(
  QuizFormat format, {
  List<Question> questions = const [question, buzzer],
}) => Quiz(
  id: 'quiz',
  name: 'Recovery',
  description: 'Recovery test',
  category: 'Tests',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  questions: questions,
  teams: teams.values.toList(),
  format: format,
);

QuizEngineBloc engineFor(
  Quiz quiz, {
  GameMode mode = const SoloMode(),
  SessionCheckpoint? saved,
  int Function()? now,
}) => QuizEngineBloc(
  questionBank: quiz.questions,
  teams: quiz.teamsById,
  mode: mode,
  jeopardyBoard: switch (quiz.format) {
    JeopardyFormat(:final board) => board,
    _ => null,
  },
  pokerStartingChips: switch (quiz.format) {
    PokerFormat(:final startingChips) => startingChips,
    _ => null,
  },
  revealMode: switch (quiz.format) {
    StandardFormat(:final revealMode) => revealMode,
    _ => SolutionRevealMode.afterEachQuestion,
  },
  restoredGame: saved?.pausedGame(),
  recoverySessionId: saved?.sessionId ?? sessionId,
  resumeTokenHashes: saved?.resumeTokenHashes ?? const {},
  autoContinueBuzzer: false,
  now: now ?? () => epoch,
);

Future<void> send(QuizEngineBloc engine, QuizEngineEvent event) async {
  engine.add(event);
  await pumpEventQueue();
}

Future<void> joinPlayers(QuizEngineBloc engine) async {
  for (final (id, team) in [('one', 'a'), ('two', 'b')]) {
    engine.resumeTokenHashes[id] = hashResumeToken('private-$id');
    await send(
      engine,
      PlayerJoinedEvent(Player(id: id, name: id, teamId: team)),
    );
  }
}

SessionCheckpoint capture(QuizEngineBloc engine, Quiz quiz) {
  final checkpoint = SessionCheckpoint(
    sessionId: sessionId,
    quiz: quiz,
    game: engine.state.game.copyWith(hostTimeMicros: engine.hostNowMicros),
    savedAtMicros: epoch,
    resumeTokenHashes: Map.of(engine.resumeTokenHashes),
  );
  checkpoint.validate();
  return RecoveryRecord(
    checkpoint.encode(),
    jsonEncode(quiz.toJson()),
  ).decode();
}

TrueFalseAnswer answer(
  String id, {
  int at = epoch + 2000000,
  bool value = true,
}) => TrueFalseAnswer(
  playerId: id,
  questionId: 'q',
  clientTimestampMicros: at,
  clockOffsetMicros: 0,
  value: value,
);

void main() {
  test('fixed schema 1 fixture retains accepted answers and question/solution media', () async {
    final fixture = jsonDecode(
      await File(
        p.join('test', 'fixtures', 'recovery', 'schema_v1_payload.json'),
      ).readAsString(),
    ) as Map<String, dynamic>;
    final quizDocument = jsonEncode(fixture.remove('quiz'));
    final version = fixture.remove('schemaVersion');
    fixture['quizSha256'] = sha256
        .convert(utf8.encode(quizDocument))
        .toString();
    final payload = jsonEncode(fixture);
    final saved = SessionCheckpoint.decode(
      jsonEncode({
        'schemaVersion': version,
        'payload': payload,
        'sha256': sha256.convert(utf8.encode(payload)).toString(),
      }),
      quizDocument: quizDocument,
    );
    expect(saved.game.round.answers['p'], isA<TrueFalseAnswer>());
    expect(saved.game.corrections, isEmpty);
    expect(jsonDecode(saved.encode())['schemaVersion'], 2);
    expect(
      saved.quiz.questions.single.media.single.asset!.bytes,
      saved.quiz.questions.single.solutionMedia.single.asset!.bytes,
    );
    expect(
      saved.game.round.elapsedAt(saved.game.hostTimeMicros),
      const Duration(seconds: 2),
    );
    expect(
      RecoveryRecord(
        saved.encode(),
        jsonEncode(saved.quiz.toJson()),
      ).decode().game,
      saved.game,
    );
  });

  for (final format in <QuizFormat>[
    const StandardFormat(),
    const JeopardyFormat(board),
    const PokerFormat(startingChips: 100),
  ]) {
    for (final mode in <GameMode>[
      const SoloMode(),
      const TeamMode(),
      const TeamMode(sharedBuzzer: false),
    ]) {
      test(
        'preserves ${format.runtimeType} / $mode through accepted answers and repeated resume',
        () async {
          var now = epoch;
          final quiz = quizFor(format);
          final engine = engineFor(quiz, mode: mode, now: () => now);
          addTearDown(engine.close);
          await joinPlayers(engine);
          await send(engine, const StartRoundEvent('q'));
          if (format is PokerFormat) {
            await send(
              engine,
              const PlacePokerWagerEvent(
                playerId: 'one',
                questionId: 'q',
                wager: 20,
              ),
            );
            await send(
              engine,
              const PlacePokerWagerEvent(
                playerId: 'two',
                questionId: 'q',
                wager: 30,
              ),
            );
            await send(engine, const OpenPokerAnswersEvent());
          }
          now += 2000000;
          await send(engine, SubmitAnswerEvent(answer('one')));
          final saved = capture(engine, quiz);
          final restored = engineFor(
            quiz,
            saved: saved,
            now: () => now + 900000000,
          );
          addTearDown(restored.close);
          expect(restored.state.game.recoveryPaused, isTrue);
          expect(restored.state.game.connectedPlayers, isEmpty);
          expect(restored.state.game.round.answers, saved.game.round.answers);
          expect(restored.state.game.scores, saved.game.scores);
          expect(restored.state.game.jeopardy, saved.game.jeopardy);
          expect(restored.state.game.poker, saved.game.poker);
          await send(restored, const RevealRoundEvent());
          expect(restored.state.game.round.status, saved.game.round.status);
          await send(
            restored,
            const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
          );
          await send(
            restored,
            const ResumeRecoveredGameEvent(RecoveryTimerPolicy.restart),
          );
          expect(
            restored.state.game.round.elapsedAt(restored.hostNowMicros),
            const Duration(seconds: 2),
          );
          await send(
            restored,
            SubmitAnswerEvent(
              answer('one', at: restored.hostNowMicros, value: false),
            ),
          );
          expect(
            restored.state.game.round.answers['one'],
            isA<TrueFalseAnswer>().having(
              (a) => a.value,
              'accepted value',
              true,
            ),
          );
          await send(restored, const RevealRoundEvent());
          final totals = restored.state.game.teamScores;
          final scores = restored.state.game.scores;
          final secondSave = capture(restored, quiz);
          final twice = engineFor(
            quiz,
            saved: secondSave,
            now: () => now + 1800000000,
          );
          addTearDown(twice.close);
          await send(
            twice,
            const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
          );
          await send(twice, const RevealRoundEvent());
          expect(twice.state.game.scores, scores);
          expect(twice.state.game.teamScores, totals);
          expect(
            twice.state.game.completedQuestionIds,
            restored.state.game.completedQuestionIds,
          );
        },
      );
    }
  }

  test('preserves daily-double wager, steal progress, pending picks and reserved poker chips', () async {
    final quiz = quizFor(const JeopardyFormat(board));
    final engine = engineFor(quiz, mode: const TeamMode());
    addTearDown(engine.close);
    await joinPlayers(engine);
    await send(engine, const SelectJeopardyCellEvent('buzz'));
    expect(capture(engine, quiz).game.jeopardy!.pendingDailyDoubleId, 'buzz');
    await send(engine, const PlaceDailyDoubleWagerEvent(150));
    expect(capture(engine, quiz).game.jeopardy!.activePoints, 150);
    expect(capture(engine, quiz).game.jeopardy!.activeIsDailyDouble, isTrue);
    await send(engine, const EndRoundEvent());
    await send(engine, const CloseRoundEvent());
    await send(engine, const SetJeopardyTurnEvent('a'));
    await send(engine, const StartRoundEvent('q'));
    await send(
      engine,
      const SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'one',
          questionId: 'q',
          clientTimestampMicros: epoch,
          clockOffsetMicros: 0,
          value: false,
        ),
      ),
    );
    expect(capture(engine, quiz).game.jeopardy!.isStealRound, isTrue);
    final pokerQuiz = quizFor(const PokerFormat(startingChips: 100));
    final poker = engineFor(pokerQuiz);
    addTearDown(poker.close);
    await joinPlayers(poker);
    await send(poker, const StartRoundEvent('q'));
    await send(
      poker,
      const PlacePokerWagerEvent(playerId: 'one', questionId: 'q', wager: 40),
    );
    final saved = capture(poker, pokerQuiz);
    final restored = engineFor(pokerQuiz, saved: saved);
    addTearDown(restored.close);
    await send(
      restored,
      const PlacePokerWagerEvent(playerId: 'one', questionId: 'q', wager: 10),
    );
    expect(restored.state.game.poker!.chips['a'], 60);
    await send(
      restored,
      const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
    );
    await send(
      restored,
      const PlacePokerWagerEvent(playerId: 'one', questionId: 'q', wager: 10),
    );
    expect(restored.state.game.poker!.chips['a'], 90);
  });

  test('retains both media sides, deferred results and score history but exports no credentials', () async {
    final asset = MediaAsset.upload(
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      'png',
    );
    final mediaQuestion = TrueFalseQuestion(
      id: 'q',
      prompt: 'Image?',
      correctAnswer: true,
      media: [ImageAttachment(asset: asset)],
      solutionMedia: [ImageAttachment(asset: asset)],
    );
    final quiz = quizFor(
      const StandardFormat(revealMode: SolutionRevealMode.atEnd),
      questions: [mediaQuestion, buzzer],
    );
    final engine = engineFor(quiz);
    addTearDown(engine.close);
    await joinPlayers(engine);
    await send(engine, const StartRoundEvent('q'));
    await send(engine, SubmitAnswerEvent(answer('one', at: epoch)));
    await send(engine, const RevealRoundEvent());
    final saved = capture(engine, quiz);
    expect(saved.game.roundHistory, hasLength(1));
    expect(
      saved
          .game
          .roundHistory
          .single
          .question!
          .solutionMedia
          .single
          .asset!
          .bytes,
      asset.bytes,
    );
    expect(saved.game.scores.history, isNotEmpty);
    final redacted = saved.pausedGame().redactedForPlayers();
    expect(redacted.roundHistory, isEmpty);
    expect(redacted.round.question!.solutionMedia, isEmpty);
    expect(
      (redacted.round.question! as TrueFalseQuestion).correctAnswer,
      isNull,
    );
    expect(redacted.scores.history, isEmpty);
    expect(saved.encode(), isNot(contains('private-one')));
    expect(saved.exportReport(), isNot(contains('resumeTokenHashes')));
    expect(
      saved.exportReport(),
      isNot(contains(hashResumeToken('private-one'))),
    );
    expect(saved.encode().length, lessThan(10000));
  });

  test('strict envelope rejects damage, missing fields, fractional and future versions without replacing saved state', () async {
    final quiz = quizFor(const StandardFormat());
    final engine = engineFor(quiz);
    addTearDown(engine.close);
    final saved = capture(engine, quiz);
    final quizJson = jsonEncode(quiz.toJson());
    final encoded = saved.encode();
    expect(
      () => SessionCheckpoint.decode('bad JSON', quizDocument: quizJson),
      throwsA(isA<RecoveryException>()),
    );
    for (final version in [null, 1.5, 0, SessionCheckpoint.schemaVersion + 1]) {
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      envelope['schemaVersion'] = version;
      expect(
        () => SessionCheckpoint.decode(
          jsonEncode(envelope),
          quizDocument: quizJson,
        ),
        throwsA(isA<RecoveryException>()),
      );
    }
    expect(
      () => SessionCheckpoint.decode(encoded, quizDocument: '{}'),
      throwsA(isA<RecoveryException>()),
    );
    final envelope = jsonDecode(encoded) as Map<String, dynamic>;
    final payload =
        jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
    (payload['game'] as Map<String, dynamic>).remove('scores');
    envelope['payload'] = jsonEncode(payload);
    envelope['sha256'] = sha256
        .convert(utf8.encode(envelope['payload'] as String))
        .toString();
    expect(
      () => SessionCheckpoint.decode(
        jsonEncode(envelope),
        quizDocument: quizJson,
      ),
      throwsA(isA<RecoveryException>()),
    );
  });

  for (final policy in RecoveryTimerPolicy.values) {
    test(
      'frozen downtime and ${policy.name} timer policy are explicit',
      () async {
        var now = epoch;
        final quiz = quizFor(const StandardFormat());
        final engine = engineFor(quiz, now: () => now);
        for (final (id, team) in [('one', 'a'), ('two', 'b')]) {
          engine.resumeTokenHashes[id] = hashResumeToken('private-$id');
          await send(
            engine,
            PlayerJoinedEvent(Player(id: id, name: id, teamId: team)),
          );
        }
        await send(engine, const StartRoundEvent('q'));
        now += 4000000;
        await send(engine, SubmitAnswerEvent(answer('one')));
        final saved = capture(engine, quiz);
        await engine.close();
        now += 900000000;
        final restored = engineFor(quiz, saved: saved, now: () => now);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(restored.state.game.round.status.acceptsInput, isTrue);
        expect(restored.hostNowMicros, epoch + 4000000);
        final tv = SpectatorSessionState(
          game: restored.state.game,
          snapshotReceivedAt: DateTime.utc(2026),
        );
        expect(
          tv.remainingTime(DateTime.utc(2027)),
          const Duration(seconds: 6),
        );
        await send(restored, ResumeRecoveredGameEvent(policy));
        final start = restored.state.game.round.timerStartedAtHostMicros!;
        expect(
          now - start,
          policy == RecoveryTimerPolicy.restart ? 0 : 4000000,
        );
        now += 7000000;
        await send(
          restored,
          const TimeSyncEvent(
            playerId: 'one',
            clockOffsetMicros: 0,
            roundTripMicros: 100,
          ),
        );
        expect(
          restored.state.game.round.status.acceptsInput,
          policy != RecoveryTimerPolicy.savedTime,
        );
        if (policy == RecoveryTimerPolicy.soft) {
          now += 60000000;
          await send(
            restored,
            const TimeSyncEvent(
              playerId: 'one',
              clockOffsetMicros: 0,
              roundTripMicros: 101,
            ),
          );
          expect(restored.state.game.round.status.acceptsInput, isTrue);
        }
        if (policy == RecoveryTimerPolicy.restart) {
          await send(restored, const RevealRoundEvent());
          expect(restored.state.game.scores.scoreOf('one'), 18);
        }
        await restored.close();
      },
    );
  }

  for (final (rule, firstPoints, secondPoints) in [
    (const SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10), 18, 19),
    (const FirstBuzzerRule(points: 20, rankDecay: 5), 20, 15),
  ]) {
    test(
      'repeated full timer restarts preserve accepted timing and rank for ${rule.runtimeType}',
      () async {
        var now = epoch;
        final quiz = quizFor(
          const StandardFormat(),
          questions: [
            TrueFalseQuestion(
              id: 'q',
              prompt: 'True?',
              correctAnswer: true,
              timeLimit: const Duration(seconds: 10),
              scoringRule: rule,
            ),
          ],
        );
        var current = engineFor(quiz, now: () => now);
        final owned = <QuizEngineBloc>[current];
        addTearDown(() async {
          for (final engine in owned) {
            await engine.close();
          }
        });
        await joinPlayers(current);
        await send(current, const StartRoundEvent('q'));
        now += 2000000;
        await send(current, SubmitAnswerEvent(answer('one', at: now)));
        now += 2000000;
        for (var restart = 0; restart < 2; restart++) {
          final saved = capture(current, quiz);
          await current.close();
          now += 900000000;
          current = engineFor(quiz, saved: saved, now: () => now);
          owned.add(current);
          await joinPlayers(current);
          await send(
            current,
            const ResumeRecoveredGameEvent(RecoveryTimerPolicy.restart),
          );
          expect(current.state.game.round.timerElapsedAt(now), Duration.zero);
          expect(
            current.state.game.round.answers['one']!.hostTimestampMicros,
            lessThan(now),
          );
          expect(
            current.state.game.round.acceptedElapsedMicros['one'],
            2000000,
          );
          now += 1000000;
        }
        await send(current, SubmitAnswerEvent(answer('two', at: now)));
        await send(current, const RevealRoundEvent());
        expect(current.state.game.scores.scoreOf('one'), firstPoints);
        expect(current.state.game.scores.scoreOf('two'), secondPoints);
      },
    );
  }

  test('atomic file replacement retains last commit, excludes incomplete temp file and locks duplicate hosts', () async {
    final directory = await Directory.systemTemp.createTemp('quizmo-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileSessionRecoveryStore(directory);
    final quiz = quizFor(const StandardFormat());
    final engine = engineFor(quiz);
    addTearDown(engine.close);
    final saved = capture(engine, quiz);
    await store.acquire();
    await store.write(saved.encode(), jsonEncode(quiz.toJson()));
    await File(p.join(directory.path, 'session.pending'))
        .writeAsString('interrupted');
    expect((await store.read())!.decode().game, saved.game);
    final other = FileSessionRecoveryStore(directory);
    await expectLater(other.acquire(), throwsA(isA<RecoveryException>()));
    await store.write(saved.encode(), jsonEncode(quiz.toJson()));
    final blocked = Directory(p.join(directory.path, 'session.pending'));
    await blocked.create();
    await expectLater(
      store.write('cannot commit', jsonEncode(quiz.toJson())),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.read())!.decode().game, saved.game);
    await blocked.delete();
    await store.release();
    await other.acquire();
    expect((await other.read())!.decode().game, saved.game);
    await other.delete();
    expect(await other.read(), isNull);
    await other.release();
  });

  test('save failures retain durable data, expose errors, retry and serialize coalesced writes', () async {
    final store = MemoryRecoveryStore();
    final quiz = quizFor(const StandardFormat());
    final engine = engineFor(quiz);
    addTearDown(engine.close);
    final recovery = SessionRecovery(engine: engine, quiz: quiz, store: store);
    await recovery.start();
    final first = store.record!;
    store.failWrites = true;
    final error = recovery.errors.first;
    await expectLater(recovery.checkpoint(), throwsA(isA<RecoveryException>()));
    expect(await error, isA<RecoveryException>());
    expect(store.record!.matches(first), isTrue);
    expect(recovery.lastError, isNotNull);
    store.failWrites = false;
    await recovery.checkpoint();
    expect(recovery.lastError, isNull);
    await send(
      engine,
      const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
    );
    store.writeBarrier = Completer<void>();
    final pending = recovery.checkpoint();
    await send(engine, const StartGameEvent());
    final newest = recovery.checkpoint();
    store.writeBarrier!.complete();
    await Future.wait([pending, newest]);
    expect(store.record!.decode().game.isStarted, isTrue);
    await recovery.close();
    expect(store.locked, isFalse);
    final stale = SessionRecovery(engine: engine, quiz: quiz, store: store);
    await expectLater(stale.start(), throwsA(isA<RecoveryException>()));
    expect(store.locked, isFalse);
  });

  test('interrupted buzzer grace retains ordering and judged locked state is not scored twice', () async {
    var now = epoch;
    final quiz = quizFor(const StandardFormat());
    final engine = engineFor(quiz, now: () => now);
    addTearDown(engine.close);
    await joinPlayers(engine);
    await send(engine, const StartRoundEvent('buzz'));
    now += 1000000;
    await send(
      engine,
      const BuzzerPressEvent(
        BuzzerPress(
          playerId: 'one',
          questionId: 'buzz',
          clientTimestampMicros: epoch + 1000,
          clockOffsetMicros: 0,
        ),
      ),
    );
    await send(
      engine,
      const BuzzerPressEvent(
        BuzzerPress(
          playerId: 'two',
          questionId: 'buzz',
          clientTimestampMicros: epoch + 1500,
          clockOffsetMicros: 1000,
        ),
      ),
    );
    final saved = capture(engine, quiz);
    await engine.close();
    expect(saved.game.round.buzzerQueue.map((p) => p.playerId), ['two', 'one']);
    now += 900000000;
    final restored = engineFor(quiz, saved: saved, now: () => now);
    addTearDown(restored.close);
    await send(
      restored,
      const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
    );
    expect(restored.state.game.round.activePlayerId, 'two');
    expect(
      restored.state.game.round.gapToFastest(
        restored.state.game.round.buzzerQueue.last,
      ),
      const Duration(microseconds: 500),
    );
    final locked = capture(restored, quiz);
    final again = engineFor(quiz, saved: locked, now: () => now + 900000000);
    addTearDown(again.close);
    await send(
      again,
      const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
    );
    await send(again, const JudgeBuzzerEvent(wasCorrect: true));
    final scores = again.state.game.scores;
    await send(again, const JudgeBuzzerEvent(wasCorrect: true));
    expect(again.state.game.scores, scores);
    expect(scores.scoreOf('two'), greaterThan(0));
  });

  test('manual verdict correction survives before reveal without exposing the solution', () async {
    const manual = ShortAnswerQuestion(
      id: 'q',
      prompt: 'Name?',
      acceptedAnswers: ['Secret'],
      manualGrading: true,
    );
    final quiz = quizFor(const StandardFormat(), questions: [manual]);
    final engine = engineFor(quiz);
    addTearDown(engine.close);
    await joinPlayers(engine);
    await send(engine, const StartRoundEvent('q'));
    await send(
      engine,
      const SubmitAnswerEvent(
        ShortAnswer(
          playerId: 'one',
          questionId: 'q',
          clientTimestampMicros: epoch,
          clockOffsetMicros: 0,
          text: 'Secret',
        ),
      ),
    );
    await send(
      engine,
      const JudgeAnswerEvent(
        playerId: 'one',
        questionId: 'q',
        startedAtHostMicros: epoch,
        wasCorrect: false,
      ),
    );
    await send(
      engine,
      const JudgeAnswerEvent(
        playerId: 'one',
        questionId: 'q',
        startedAtHostMicros: epoch,
        wasCorrect: true,
      ),
    );
    final saved = capture(engine, quiz);
    expect(saved.game.round.answerVerdicts, {'one': 1});
    expect(saved.game.redactedForPlayers().round.answerVerdicts, isEmpty);
    final restored = engineFor(
      quiz,
      saved: saved,
      now: () => epoch + 900000000,
    );
    addTearDown(restored.close);
    await send(
      restored,
      const ResumeRecoveredGameEvent(RecoveryTimerPolicy.savedTime),
    );
    await send(restored, const RevealRoundEvent());
    expect(restored.state.game.scores.scoreOf('one'), 10);
  });

  test(
    'periodic save advances elapsed time without an engine transition',
    () async {
      var now = epoch;
      final quiz = quizFor(const StandardFormat());
      final engine = engineFor(quiz, now: () => now);
      final store = MemoryRecoveryStore();
      final recovery = SessionRecovery(
        engine: engine,
        quiz: quiz,
        store: store,
        interval: const Duration(milliseconds: 10),
      );
      await recovery.start();
      await send(engine, const StartRoundEvent('q'));
      await recovery.checkpoint();
      now += 3000000;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(store.record!.decode().game.hostTimeMicros, now);
      expect(
        store.record!.decode().game.round.elapsedAt(now),
        const Duration(seconds: 3),
      );
      await recovery.close();
      await engine.close();
    },
  );
}
