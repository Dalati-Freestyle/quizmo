import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const _question = ShortAnswerQuestion(
  id: 'q',
  prompt: 'Capital?',
  acceptedAnswers: ['Berlin'],
  manualGrading: true,
  timeLimit: Duration.zero,
);

void main() {
  late QuizEngineBloc engine;
  var now = 1000000;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  GameState game() => engine.state.game;

  Future<void> start({
    int? poker,
    JeopardyBoard? board,
    Map<String, String?> players = const {'a1': 'a', 'b1': 'b', 'c1': 'c'},
    SolutionRevealMode revealMode = SolutionRevealMode.afterEachQuestion,
  }) async {
    now = 1000000;
    final teams = players.values.whereType<String>().toSet();
    engine = QuizEngineBloc(
      questionBank: const [_question],
      teams: {for (final id in teams) id: Team(id: id, name: id)},
      mode: teams.isEmpty ? const SoloMode() : const TeamMode(),
      pokerStartingChips: poker,
      jeopardyBoard: board,
      revealMode: revealMode,
      now: () => now,
    );
    addTearDown(engine.close);
    for (final entry in players.entries) {
      await send(
        PlayerJoinedEvent(
          Player(id: entry.key, name: entry.key, teamId: entry.value),
        ),
      );
    }
    if (board == null) await send(const StartRoundEvent('q'));
  }

  Future<void> answer(String player, String text) => send(
    SubmitAnswerEvent(
      ShortAnswer(
        playerId: player,
        questionId: 'q',
        clientTimestampMicros: now,
        clockOffsetMicros: 0,
        text: text,
      ),
    ),
  );

  Future<void> confirm(Map<String, bool> grades, {int? startedAt}) => send(
    ConfirmGradesEvent(
      questionId: 'q',
      startedAtHostMicros: startedAt ?? game().round.startedAtHostMicros!,
      grades: {
        for (final entry in grades.entries)
          entry.key: (correct: entry.value, reason: ''),
      },
    ),
  );

  test('all verdicts are booked and revealed in one step', () async {
    await start();
    await answer('a1', 'Berlin');
    await answer('b1', 'Bonn');
    await send(const RevealRoundEvent());
    expect(game().round.status, RoundStatus.locked);
    final states = <QuizEngineState>[];
    final subscription = engine.stream.listen(states.add);
    await confirm({'a1': true, 'b1': false});
    await subscription.cancel();
    expect(states, hasLength(1), reason: 'everybody gets the same state');
    expect(game().round.status, RoundStatus.revealed);
    expect(game().teamScores, {'a': 10, 'b': 0, 'c': 0});
    expect(game().corrections, hasLength(2));
    // Confirming twice changes nothing.
    await confirm({'a1': true, 'b1': true});
    expect(game().teamScores, {'a': 10, 'b': 0, 'c': 0});
  });

  test(
    'every given answer needs a verdict, stale rounds are refused',
    () async {
      await start();
      await answer('a1', 'Berlin');
      await answer('b1', 'Bonn');
      await confirm({'a1': true, 'b1': true});
      expect(game().round.status, RoundStatus.acceptingAnswers);
      await send(const RevealRoundEvent());
      await confirm({'a1': true});
      expect(game().round.status, RoundStatus.locked);
      expect(game().round.answerVerdicts, isEmpty);
      await confirm({'a1': true, 'b1': true}, startedAt: 1);
      expect(game().round.status, RoundStatus.locked);
    },
  );

  test('nobody answered: closing waits, confirming reveals', () async {
    await start();
    await send(const RevealRoundEvent());
    expect(game().round.status, RoundStatus.locked);
    await confirm(const {});
    expect(game().round.status, RoundStatus.revealed);
  });

  test('a player who leaves while the host judges still counts', () async {
    await start();
    await answer('a1', 'Berlin');
    await send(const RevealRoundEvent());
    await send(const PlayerLeftEvent('a1'));
    await confirm({'a1': true});
    expect(game().teamScores['a'], 10);
  });

  test('chips move only with the confirmation', () async {
    await start(poker: 100);
    for (final id in ['a1', 'b1', 'c1']) {
      await send(
        PlacePokerWagerEvent(playerId: id, questionId: 'q', wager: 30),
      );
    }
    await send(const OpenPokerAnswersEvent());
    await answer('a1', 'Berlin');
    await answer('b1', 'Bonn');
    await send(const RevealRoundEvent());
    final before = game().poker!.chips;
    expect(guestSnapshotOf(game(), title: 'x').round.answerVerdicts, isEmpty);
    expect(game().poker!.chips, before);
    await confirm({'a1': true, 'b1': false});
    expect(game().poker!.chips, {'a': 130, 'b': 70, 'c': 70});
  });

  test('a miss on the board opens the steal round after confirming', () async {
    await start(
      board: const JeopardyBoard(
        rowPoints: [100],
        categories: [
          JeopardyCategory(
            name: 'C',
            cells: [JeopardyCell(questionId: 'q')],
          ),
        ],
      ),
      players: const {'a1': 'a', 'b1': 'b'},
    );
    await send(const StartGameEvent());
    await send(const SelectJeopardyCellEvent('q'));
    await answer('a1', 'Bonn');
    expect(game().round.status, RoundStatus.locked);
    final first = game().round.startedAtHostMicros;
    now += 1000000;
    await confirm({'a1': false});
    expect(game().jeopardy!.isStealRound, isTrue);
    expect(game().round.status, RoundStatus.acceptingAnswers);
    expect(game().round.startedAtHostMicros, isNot(first));
    expect(
      guestSnapshotOf(game(), title: 'x').round.question!.hasSolution,
      isFalse,
    );
    await answer('b1', 'Berlin');
    await confirm({'b1': true});
    expect(game().teamScores['b'], 100);
  });

  test('"solutions at the end" scores but shows nothing yet', () async {
    await start(revealMode: SolutionRevealMode.atEnd);
    await answer('a1', 'Berlin');
    await send(const RevealRoundEvent());
    await confirm({'a1': true});
    expect(game().teamScores['a'], 10);
    final guest = guestSnapshotOf(game(), title: 'x');
    expect(guest.round.answerVerdicts, isEmpty);
    expect(guest.teamScores['a'] ?? 0, 0);
  });

  test('a verbal round judges a team that typed nothing', () async {
    await start();
    await send(const SetVerbalAnswersEvent(true));
    await send(const RevealRoundEvent());
    expect(game().round.status, RoundStatus.locked);
    await confirm({'b1': true});
    expect(game().round.answers['b1'], isA<VerbalAnswer>());
    expect(game().teamScores, {'a': 0, 'b': 10, 'c': 0});
  });
}
