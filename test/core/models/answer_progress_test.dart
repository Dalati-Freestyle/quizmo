import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

const question = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Hauptstadt?',
  acceptedAnswers: ['Paris'],
);

ShortAnswer said(String player) => ShortAnswer(
  playerId: player,
  questionId: 'q',
  clientTimestampMicros: 1,
  clockOffsetMicros: 0,
  text: 'Paris',
);

/// Five players in three teams; [answered] players sent an answer.
GameState game({
  required GameMode mode,
  List<String> answered = const [],
  Question q = question,
}) => GameState(
  isStarted: true,
  mode: mode,
  teams: const {
    'a': Team(id: 'a', name: 'A'),
    'b': Team(id: 'b', name: 'B'),
    'c': Team(id: 'c', name: 'C'),
  },
  players: const {
    'p1': Player(id: 'p1', name: '1', teamId: 'a'),
    'p2': Player(id: 'p2', name: '2', teamId: 'a'),
    'p3': Player(id: 'p3', name: '3', teamId: 'b'),
    'p4': Player(id: 'p4', name: '4', teamId: 'b'),
    'p5': Player(id: 'p5', name: '5', teamId: 'c'),
    'gone': Player(id: 'gone', name: 'x', teamId: 'c', isConnected: false),
  },
  round: RoundState(
    question: q,
    status: RoundStatus.acceptingAnswers,
    startedAtHostMicros: 1,
    answers: {for (final id in answered) id: said(id)},
  ),
);

void main() {
  test('in a team game every team counts as one answer', () {
    final progress = game(
      mode: const TeamMode(),
      answered: ['p1', 'p3', 'p5'],
    ).answerProgress;
    expect(progress, (answered: 3, expected: 3, teams: true));
    final partial = game(mode: const TeamMode(), answered: ['p2']);
    expect(partial.answerProgress, (answered: 1, expected: 3, teams: true));
    expect(partial.expectedAnswerers.where(partial.hasAnswered), [
      (id: 'a', team: true),
    ]);
  });

  test('solo games count connected players', () {
    expect(
      game(mode: const SoloMode(), answered: ['p1', 'p3']).answerProgress,
      (answered: 2, expected: 5, teams: false),
    );
  });

  test('buzzer rounds count per player, also in a team game', () {
    final buzzer = game(
      mode: const TeamMode(),
      q: const BuzzerQuestion(id: 'q', prompt: 'Wer?'),
    );
    expect(buzzer.answerProgress, (answered: 0, expected: 5, teams: false));
  });
}
