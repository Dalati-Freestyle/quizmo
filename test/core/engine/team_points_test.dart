import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/session_checkpoint.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const _epoch = 1700000000000000;
const _question = TrueFalseQuestion(id: 'q', prompt: 'Q?', correctAnswer: true);
const _teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

/// With teams, points belong to the team, not to the player who earned them.
void main() {
  late QuizEngineBloc engine;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> scoreForTeamA() async {
    engine = QuizEngineBloc(
      questionBank: const [_question],
      teams: _teams,
      mode: const TeamMode(),
      now: () => _epoch,
    );
    addTearDown(engine.close);
    await send(
      const PlayerJoinedEvent(Player(id: 'p1', name: 'One', teamId: 'a')),
    );
    await send(
      const PlayerJoinedEvent(Player(id: 'p2', name: 'Two', teamId: 'b')),
    );
    await send(const StartRoundEvent('q'));
    await send(
      const SubmitAnswerEvent(
        TrueFalseAnswer(
          playerId: 'p1',
          questionId: 'q',
          clientTimestampMicros: _epoch,
          clockOffsetMicros: 0,
          value: true,
        ),
      ),
    );
    await send(const RevealRoundEvent());
    expect(engine.state.game.teamScores['a'], greaterThan(0));
  }

  test('points stay with the team when the player changes teams', () async {
    await scoreForTeamA();
    final earned = engine.state.game.teamScores['a']!;
    await send(const AssignTeamEvent(playerId: 'p1', teamId: 'b'));
    final game = engine.state.game;
    expect(game.teamScores['a'], earned);
    expect(game.teamScores['b'], 0);
    expect(game.scores.scoreOf('p1'), 0);
    // The win of the question is kept for the protocol.
    expect(game.questionWinners['q'], isNotNull);
  });

  test('points stay with the team when the player is removed', () async {
    await scoreForTeamA();
    final earned = engine.state.game.teamScores['a']!;
    await send(const KickPlayerEvent('p1'));
    expect(engine.state.game.players.containsKey('p1'), isFalse);
    expect(engine.state.game.teamScores['a'], earned);
  });

  test('a handover survives a checkpoint round trip', () async {
    await scoreForTeamA();
    await send(const AssignTeamEvent(playerId: 'p1', teamId: 'b'));
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
      sessionId: 'session-team-points-1234',
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
  });
}
