import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const _epoch = 1700000000000000;
const _question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Question',
  options: [
    AnswerOption(id: 'a', label: 'A'),
    AnswerOption(id: 'b', label: 'B'),
  ],
  correctOptionId: 'a',
);
const _teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

void main() {
  late QuizEngineBloc engine;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> start({bool teams = true, bool poker = false}) async {
    engine = QuizEngineBloc(
      questionBank: const [_question],
      teams: _teams,
      mode: teams || poker ? const TeamMode() : const SoloMode(),
      pokerStartingChips: poker ? 100 : null,
      now: () => _epoch,
    );
    addTearDown(engine.close);
    await send(
      PlayerJoinedEvent(
        Player(id: 'p1', name: 'One', teamId: teams || poker ? 'a' : null),
      ),
    );
    await send(
      PlayerJoinedEvent(
        Player(id: 'p2', name: 'Two', teamId: teams || poker ? 'b' : null),
      ),
    );
  }

  CorrectScoreEvent change(
    String id,
    int delta, {
    String? playerId,
    String? teamId,
    String reason = 'Bonus',
  }) => CorrectScoreEvent(
    requestId: id,
    playerId: playerId,
    teamId: teamId,
    delta: delta,
    reason: reason,
  );

  group('reason is mandatory', () {
    test('empty and blank reasons are rejected by the engine', () async {
      await start(teams: false);
      await send(change('empty', 5, playerId: 'p1', reason: ''));
      await send(change('blank', 5, playerId: 'p1', reason: '   \n\t'));
      expect(engine.state.game.corrections, isEmpty);
      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.notice, 'Bitte eine Begründung angeben.');
    });

    test('the shrug emoji is a valid reason and is stored trimmed', () async {
      await start(teams: false);
      await send(
        change('shrug', 5, playerId: 'p1', reason: ' $kNoReasonGiven '),
      );
      expect(engine.state.game.corrections.single.reason, kNoReasonGiven);
      expect(engine.state.game.scores.scoreOf('p1'), 5);
    });
  });

  test('a change is possible before the first and between questions', () async {
    await start(teams: false);
    expect(engine.state.game.round.question, isNull);
    await send(change('lobby', 7, playerId: 'p1'));
    expect(engine.state.game.scores.scoreOf('p1'), 7);
    final entry = engine.state.game.corrections.single;
    expect(entry.questionId, isNull);
    expect(entry.roundStartedAt, isNull);
    expect(engine.state.game.scores.history.single.questionId, isEmpty);
    await send(const StartRoundEvent('q'));
    await send(const RevealRoundEvent());
    await send(change('after', -2, playerId: 'p2'));
    expect(engine.state.game.scores.scoreOf('p2'), -2);
    expect(engine.state.game.questionWinners, isEmpty);
  });

  group('team targets', () {
    test('a team is changed directly without a player', () async {
      await start();
      await send(change('team', 10, teamId: 'b'));
      final game = engine.state.game;
      expect(game.teamScores['b'], 10);
      expect(game.scores.scoreOf('p2'), 0);
      expect(game.scores.byTeam, {'b': 10});
      final entry = game.corrections.single;
      expect(entry.targetsTeam, isTrue);
      expect(entry.teamId, 'b');
      expect(entry.participantName, 'B');
      expect(entry.beforeValue, 0);
      expect(entry.afterValue, 10);
      expect(entry.teamDeltas, {'b': 10});
    });

    test('a change for a player is booked on the team', () async {
      await start();
      await send(change('player', 4, playerId: 'p1'));
      expect(engine.state.game.scores.scoreOf('p1'), 0);
      expect(engine.state.game.scores.byTeam, {'a': 4});
      expect(engine.state.game.corrections.single.targetsTeam, isTrue);
      await send(change('team', -6, teamId: 'a'));
      expect(engine.state.game.teamScores['a'], -2);
      expect(engine.state.game.corrections.last.beforeValue, 4);
      expect(engine.state.game.corrections.last.afterValue, -2);
    });

    test('team changes can be undone like other entries', () async {
      await start();
      await send(change('team', 10, teamId: 'a'));
      await send(change('later', 3, playerId: 'p1'));
      final original = engine.state.game.corrections.first;
      expect(engine.correctionUndoError(original), isNull);
      await send(UndoCorrectionEvent(original.id));
      final game = engine.state.game;
      expect(game.teamScores['a'], 3);
      expect(game.scores.byTeam, {'a': 3});
      expect(game.corrections.last.reversesId, original.id);
      expect(game.corrections.last.teamDeltas, {'a': -10});
    });

    test('solo sessions reject team targets', () async {
      await start(teams: false);
      await send(change('team', 10, teamId: 'a'));
      expect(engine.state.game.corrections, isEmpty);
    });

    test('exactly one target is required', () async {
      await start();
      await send(change('none', 10));
      await send(change('both', 10, playerId: 'p1', teamId: 'a'));
      await send(change('unknown', 10, teamId: 'zzz'));
      expect(engine.state.game.corrections, isEmpty);
    });

    test('reset clears direct team points', () async {
      await start();
      await send(change('team', 10, teamId: 'a'));
      await send(const ResetGameEvent());
      expect(engine.state.game.teamScores['a'] ?? 0, 0);
      expect(engine.state.game.scores.byTeam, isEmpty);
    });
  });

  group('poker chips', () {
    test('teams get and lose chips, never below zero', () async {
      await start(poker: true);
      await send(change('gain', 15, teamId: 'a'));
      expect(engine.state.game.poker!.chips['a'], 115);
      expect(engine.state.game.corrections.single.kind, CorrectionKind.chips);
      await send(change('loss', -116, teamId: 'b'));
      expect(engine.state.game.poker!.chips['b'], 100);
      expect(
        engine.state.notice,
        'Die Korrektur würde negative Chips erzeugen.',
      );
      await send(change('player', -100, playerId: 'p2'));
      expect(engine.state.game.poker!.chips['b'], 0);
    });
  });

  test('the reason never reaches players or the TV during the game', () async {
    await start();
    await send(change('secret', 5, teamId: 'a', reason: 'Secret reason'));
    final redacted = jsonEncode(
      engine.state.game.redactedForPlayers().toJson(),
    );
    expect(redacted, isNot(contains('Secret reason')));
    expect(engine.state.game.redactedForPlayers().teamScores['a'], 5);
  });

  test('the report export keeps target, amount and emoji reason', () async {
    await start();
    await send(change('team', 10, teamId: 'b', reason: kNoReasonGiven));
    await send(change('player', -3, playerId: 'p1', reason: 'Zu laut'));
    final report = SessionReport.fromGame(engine.state.game, title: 'Quiz');
    expect(report.corrections.first['entity_type'], 'team');
    expect(report.corrections.first['entity_id'], 'b');
    expect(report.corrections.first['score_delta'], 10);
    expect(report.corrections.first['reason'], kNoReasonGiven);
    expect(report.corrections.last['score_delta'], -3);
    final csv = report.toCsv();
    expect(csv, contains(kNoReasonGiven));
    expect(csv, contains('Zu laut'));
  });

  test('free and team changes survive a checkpoint round trip', () async {
    await start();
    await send(change('team', 10, teamId: 'a'));
    await send(change('player', 4, playerId: 'p2'));
    await send(UndoCorrectionEvent(engine.state.game.corrections.first.id));
    await send(change('again', 2, teamId: 'a'));
    final quiz = Quiz(
      id: 'quiz',
      name: 'Quiz',
      description: 'Fixture',
      category: 'Tests',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      questions: const [_question],
      teams: _teams.values.toList(),
    );
    final checkpoint = SessionCheckpoint(
      sessionId: 'session-free-points-1234',
      quiz: quiz,
      game: engine.state.game,
      savedAtMicros: _epoch,
      resumeTokenHashes: {'p1': 'a' * 64, 'p2': 'b' * 64},
    );
    checkpoint.validate();
    final saved = SessionCheckpoint.decode(
      checkpoint.encode(),
      quizDocument: jsonEncode(quiz.toJson()),
    );
    expect(saved.game.scores, engine.state.game.scores);
    expect(saved.game.corrections, engine.state.game.corrections);
    expect(saved.game.teamScores['a'], 2);

    final tampered = engine.state.game.toJson();
    (tampered['scores']! as Map<String, Object?>)['byTeam'] = {'a': 99};
    expect(
      () => SessionCheckpoint(
        sessionId: checkpoint.sessionId,
        quiz: quiz,
        game: GameState.fromJson(tampered),
        savedAtMicros: _epoch,
        resumeTokenHashes: checkpoint.resumeTokenHashes,
      ).validate(),
      throwsA(isA<RecoveryException>()),
    );
  });
}
