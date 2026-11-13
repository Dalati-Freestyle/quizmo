import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

const _epoch = 1700000000000000;
const _q1 = MultipleChoiceQuestion(
  id: 'q1',
  prompt: 'Größte Stadt? 🏙️',
  options: [
    AnswerOption(id: 'a', label: 'München'),
    AnswerOption(id: 'b', label: 'Berlin'),
  ],
  correctOptionId: 'b',
);
const _q2 = TrueFalseQuestion(
  id: 'q2',
  prompt: 'Ist Wasser nass?',
  correctAnswer: true);
const _teams = {
  'red': Team(id: 'red', name: 'Rot'),
  'blue': Team(id: 'blue', name: 'Blau'),
};

void main() {
  late QuizEngineBloc engine;

  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  Future<void> join(String id, String name, [String? team]) =>
      send(PlayerJoinedEvent(Player(id: id, name: name, teamId: team)));

  Future<void> choose(String player, String questionId, String option) => send(
    SubmitAnswerEvent(
      MultipleChoiceAnswer(
        playerId: player,
        questionId: questionId,
        clientTimestampMicros: engine.hostNowMicros,
        clockOffsetMicros: 0,
        optionId: option,
      ),
    ),
  );

  Future<void> judge(String player, String questionId, bool value) => send(
    SubmitAnswerEvent(
      TrueFalseAnswer(
        playerId: player,
        questionId: questionId,
        clientTimestampMicros: engine.hostNowMicros,
        clockOffsetMicros: 0,
        value: value,
      ),
    ),
  );

  QuizEngineBloc create({bool teams = false, int? poker}) {
    final bloc = QuizEngineBloc(
      questionBank: const [_q1, _q2],
      teams: teams || poker != null ? _teams : const {},
      mode: teams || poker != null ? const TeamMode() : const SoloMode(),
      pokerStartingChips: poker,
      now: () => _epoch,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> playSolo() async {
    engine = create();
    await join('p1', 'Anna');
    await join('p2', 'Ben');
    await join('p3', 'Cem');
    await send(const StartRoundEvent('q1'));
    await choose('p1', 'q1', 'b');
    await choose('p2', 'q1', 'b');
    await choose('p3', 'q1', 'a');
    await send(const RevealRoundEvent());
    await send(const StartRoundEvent('q2'));
    await judge('p1', 'q2', true);
    await judge('p2', 'q2', true);
    await send(const RevealRoundEvent());
    await send(const FinishQuizEvent());
  }

  test('no protocol is sent while the game is running', () async {
    engine = create();
    await join('p1', 'Anna');
    await send(const StartRoundEvent('q1'));
    await choose('p1', 'q1', 'b');
    await send(
      const CorrectScoreEvent(
        requestId: 'r',
        playerId: 'p1',
        delta: 3,
        reason: 'Geheimer Grund',
      ),
    );
    final snapshot = guestSnapshotOf(engine.state.game, title: 'Quiz');
    expect(snapshot.protocol, isNull);
    final wire = jsonEncode(snapshot.toJson());
    expect(wire, isNot(contains('Geheimer Grund')));
    expect(wire, isNot(contains('"protocol"')));
  });

  test('a finished solo game ranks players with shared places', () async {
    await playSolo();
    final game = engine.state.game;
    expect(game.isFinished, isTrue);
    final protocol = guestSnapshotOf(game, title: 'Stadtquiz').protocol!;
    expect(protocol.title, 'Stadtquiz');
    expect(protocol.format, ProtocolFormat.standard);
    expect(protocol.teamMode, isFalse);
    final standings = protocol.standings;
    expect(standings.map((s) => s.name), ['Anna', 'Ben', 'Cem']);
    expect(standings[0].score, standings[1].score);
    expect(standings.map((s) => s.place), [1, 1, 3]);
    expect(protocol.standingOf('p2')!.place, 1);
    expect(protocol.standingOf('p3')!.place, 3);
  });

  test('questions list solutions and the answers of all players', () async {
    await playSolo();
    final protocol = guestSnapshotOf(
      engine.state.game,
      title: 'Quiz',
    ).protocol!;
    expect(protocol.questions, hasLength(2));
    final first = protocol.questions.first;
    expect(first.number, 1);
    expect(first.prompt, 'Größte Stadt? 🏙️');
    expect(first.solution, 'Berlin');
    expect(first.answers, hasLength(3));
    final cem = first.answers.firstWhere((a) => a.player == 'Cem');
    expect(cem.answer, 'München');
    expect(cem.status, ProtocolAnswerStatus.incorrect);
    final anna = first.answers.firstWhere((a) => a.player == 'Anna');
    expect(anna.status, ProtocolAnswerStatus.correct);
    expect(anna.points, greaterThan(0));
    final second = protocol.questions.last;
    expect(
      second.answers.firstWhere((a) => a.player == 'Cem').status,
      ProtocolAnswerStatus.noAnswer,
    );
  });

  test(
    'the protocol carries corrections with reasons and survives JSON',
    () async {
      engine = create(teams: true);
      await join('p1', 'Anna', 'red');
      await join('p2', 'Ben', 'blue');
      await send(
        const CorrectScoreEvent(
          requestId: 'bonus',
          teamId: 'blue',
          delta: 50,
          reason: kNoReasonGiven,
        ),
      );
      await send(const StartRoundEvent('q1'));
      await choose('p1', 'q1', 'b');
      await send(const RevealRoundEvent());
      await send(const StartRoundEvent('q2'));
      await send(const RevealRoundEvent());
      await send(const FinishQuizEvent());
      final snapshot = guestSnapshotOf(engine.state.game, title: 'Teams');
      final protocol = snapshot.protocol!;
      expect(protocol.teamMode, isTrue);
      expect(protocol.standings.first.name, 'Blau');
      expect(protocol.standings.first.memberNames, ['Ben']);
      expect(protocol.standingOf('p1')!.id, 'red');
      final correction = protocol.corrections.single;
      expect(correction.kind, ProtocolCorrectionKind.points);
      expect(correction.target, 'Blau');
      expect(correction.delta, 50);
      expect(correction.reason, kNoReasonGiven);
      expect(correction.question, isNull);
      // Manual points are not attributed to a question.
      expect(
        protocol.questions
            .expand((q) => q.answers)
            .every((a) => a.points != 50),
        isTrue,
      );
      final decoded = GameState.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as JsonMap,
      );
      expect(decoded.protocol, protocol);
    },
  );

  test('poker standings use chips', () async {
    engine = create(poker: 100);
    await join('p1', 'Anna', 'red');
    await join('p2', 'Ben', 'blue');
    await send(const StartRoundEvent('q1'));
    await send(
      const PlacePokerWagerEvent(playerId: 'p1', questionId: 'q1', wager: 30),
    );
    await send(
      const PlacePokerWagerEvent(playerId: 'p2', questionId: 'q1', wager: 10),
    );
    await send(const OpenPokerAnswersEvent());
    await choose('p1', 'q1', 'b');
    await choose('p2', 'q1', 'a');
    await send(const RevealRoundEvent());
    await send(const StartRoundEvent('q2'));
    await send(const OpenPokerAnswersEvent());
    await send(const RevealRoundEvent());
    await send(const FinishQuizEvent());
    final protocol = guestSnapshotOf(
      engine.state.game,
      title: 'Poker',
    ).protocol!;
    expect(protocol.usesChips, isTrue);
    expect(protocol.standings.first.name, 'Rot');
    expect(
      protocol.standings.first.score,
      engine.state.game.poker!.chips['red'],
    );
    final anna = protocol.questions.first.answers.firstWhere(
      (a) => a.player == 'Anna',
    );
    expect(anna.wager, 30);
  });

  test('reset removes the protocol again', () async {
    await playSolo();
    await send(const ResetGameEvent());
    expect(guestSnapshotOf(engine.state.game, title: 'Q').protocol, isNull);
  });

  test('rankByScore assigns competition places', () {
    final ranked = rankByScore([5, 9, 5, 1, 9], (v) => v);
    expect(ranked.map((r) => r.$2), [1, 1, 3, 3, 5]);
  });
}
