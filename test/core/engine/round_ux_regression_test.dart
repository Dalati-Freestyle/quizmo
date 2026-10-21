import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/session_notifications.dart';

void main() {
  Future<void> send(QuizEngineBloc engine, QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  for (final soft in [false, true]) {
    test(
      '${soft ? 'soft' : 'hard'} deadline controls the answer window',
      () async {
        final engine = QuizEngineBloc(
          questionBank: [
            TrueFalseQuestion(
              id: 'q',
              prompt: '?',
              correctAnswer: true,
              timeLimit: const Duration(milliseconds: 30),
              softTimeLimit: soft,
            ),
          ],
        );
        addTearDown(engine.close);
        await send(engine, const PlayerJoinedEvent(Player(id: 'p', name: 'P')));
        await send(engine, const StartRoundEvent('q'));
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(
          engine.state.game.round.status,
          soft ? RoundStatus.acceptingAnswers : RoundStatus.locked,
        );
        await send(
          engine,
          SubmitAnswerEvent(
            TrueFalseAnswer(
              playerId: 'p',
              questionId: 'q',
              clientTimestampMicros: engine.hostNowMicros,
              clockOffsetMicros: 0,
              value: true,
            ),
          ),
        );
        expect(engine.state.game.round.answers.length, soft ? 1 : 0);
        if (soft) {
          expect(engine.state.game.round.status, RoundStatus.acceptingAnswers);
        }
        await send(engine, const RevealRoundEvent());
        expect(engine.state.game.round.status, RoundStatus.revealed);
      },
    );
  }

  test('poker answer clock starts only when host closes betting', () async {
    final engine = QuizEngineBloc(
      pokerStartingChips: 100,
      questionBank: const [
        TrueFalseQuestion(
          id: 'q',
          prompt: '?',
          correctAnswer: true,
          timeLimit: Duration(milliseconds: 30),
        ),
      ],
    );
    addTearDown(engine.close);
    await send(engine, const StartRoundEvent('q'));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(engine.state.game.round.status, RoundStatus.acceptingAnswers);
    expect(engine.state.game.poker!.betting, isTrue);
    await send(engine, const OpenPokerAnswersEvent());
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(engine.state.game.round.status, RoundStatus.locked);
  });

  test(
    'bankrupt team can answer next question but cannot earn chips',
    () async {
      final engine = QuizEngineBloc(
        pokerStartingChips: 100,
        teams: const {'a': Team(id: 'a', name: 'A')},
        questionBank: const [
          TrueFalseQuestion(id: 'q', prompt: '?', correctAnswer: true),
          TrueFalseQuestion(id: 'next', prompt: '?', correctAnswer: true),
        ],
      );
      addTearDown(engine.close);
      await send(
        engine,
        const PlayerJoinedEvent(Player(id: 'p', name: 'P', teamId: 'a')),
      );
      await send(engine, const StartRoundEvent('q'));
      await send(
        engine,
        const PlacePokerWagerEvent(playerId: 'p', questionId: 'q', wager: 100),
      );
      await send(engine, const OpenPokerAnswersEvent());
      await send(engine, const RevealRoundEvent());
      expect(engine.state.game.teamScores['a'], 0);
      await send(engine, const NextQuestionEvent());
      await send(engine, const OpenPokerAnswersEvent());
      await send(
        engine,
        SubmitAnswerEvent(
          TrueFalseAnswer(
            playerId: 'p',
            questionId: 'next',
            clientTimestampMicros: engine.hostNowMicros,
            clockOffsetMicros: 0,
            value: true,
          ),
        ),
      );
      expect(engine.state.game.round.answers.length, 1);
      expect(engine.state.game.teamScores['a'], 0);
      expect(
        roundFeedback(engine.state.game, 'p'),
        contains('Richtig! · 0 Chips'),
      );
      expect(roundFeedback(engine.state.game, 'p'), contains('keine Wertung'));
    },
  );

  test(
    'new poker teams receive starting chips without predefined roster',
    () async {
      final engine = QuizEngineBloc(pokerStartingChips: 250);
      addTearDown(engine.close);
      await send(
        engine,
        const PlayerJoinedEvent(
          Player(id: 'p', name: 'P', teamId: 'new'),
          createdTeam: Team(id: 'new', name: 'New'),
        ),
      );
      expect(engine.state.game.teamScores['new'], 250);
    },
  );

  test(
    'repeat play commands change command revision without seeking',
    () async {
      final engine = QuizEngineBloc(
        questionBank: const [TrueFalseQuestion(id: 'q', prompt: '?')],
      );
      addTearDown(engine.close);
      await send(engine, const StartRoundEvent('q'));
      for (var i = 0; i < 2; i++) {
        await send(engine, const ControlTvMediaEvent(TvMediaAction.play));
      }
      expect(engine.state.game.tvMediaCommandRevision, 2);
      expect(engine.state.game.tvMediaRevision, 0);
      await send(engine, const ControlTvMediaEvent(TvMediaAction.restart));
      expect(engine.state.game.tvMediaRevision, 1);
      expect(engine.state.game.tvMediaPaused, isFalse);
      expect(
        GameState.fromJson(engine.state.game.toJson()).tvMediaCommandRevision,
        3,
      );
    },
  );
}
