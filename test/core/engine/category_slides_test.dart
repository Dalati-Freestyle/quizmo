// "Category slide before every question" (issue #73) and the slide of the
// category in the Pokerchips category phase (issue #66).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';

MediaAsset svg(String color) => MediaAsset.upload(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10" fill="$color"/></svg>',
    ),
  ),
  'svg',
);

final questionPicture = ImageAttachment(asset: svg('red'));
final flag = ImageAttachment(asset: svg('blue'));

final germany = TrueFalseQuestion(
  id: 'q1',
  prompt: 'Berlin ist die Hauptstadt?',
  category: 'Deutschland',
  correctAnswer: true,
  media: [questionPicture],
);
const loose = TrueFalseQuestion(id: 'q2', prompt: 'Ohne Folie?');
final categorySlide = InfoSlide(
  id: 's1',
  title: 'Deutschland',
  media: [flag],
  // Spelling and case do not matter.
  category: ' deutschland ',
);

const teams = {'a': Team(id: 'a', name: 'A'), 'b': Team(id: 'b', name: 'B')};

void main() {
  late QuizEngineBloc engine;
  Future<void> send(QuizEngineEvent event) async {
    engine.add(event);
    await pumpEventQueue();
  }

  GameState game() => engine.state.game;

  group('standard quiz', () {
    setUp(() async {
      engine = QuizEngineBloc(
        questionBank: [germany, loose],
        slides: [categorySlide],
      );
      addTearDown(engine.close);
      await send(const PlayerJoinedEvent(Player(id: 'p', name: 'Ada')));
    });

    test('without the setting the question starts right away', () async {
      await send(const StartRoundEvent('q1'));
      expect(game().round.question?.id, 'q1');
      expect(game().activeSlide, isNull);
    });

    test('the slide of the category comes first, then the question', () async {
      await send(const SetCategorySlidesEvent(true));
      expect(game().categorySlides, isTrue);
      await send(const NextQuestionEvent());
      expect(game().round.question, isNull);
      expect(game().activeSlide?.id, 's1');
      expect(game().showsSlide, isTrue);
      // Guests see the slide.
      expect(game().redactedForPlayers().activeSlide?.id, 's1');

      await send(const NextQuestionEvent());
      expect(game().round.question?.id, 'q1');
      expect(game().activeSlide, isNull);
    });

    test('a question without a slide starts as before', () async {
      await send(const SetCategorySlidesEvent(true));
      await send(const StartRoundEvent('q2'));
      expect(game().round.question?.id, 'q2');
      expect(game().activeSlide, isNull);
    });

    test('the setting survives a checkpoint', () async {
      await send(const SetCategorySlidesEvent(true));
      expect(GameState.fromJson(game().toJson()).categorySlides, isTrue);
    });
  });

  group('Pokerchips', () {
    Future<void> start({
      required bool setting,
      List<Joker> jokers = const [],
    }) async {
      engine = QuizEngineBloc(
        questionBank: [germany, loose],
        slides: [categorySlide],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 10,
        jokers: jokers,
      );
      addTearDown(engine.close);
      for (final (id, team) in [('p1', 'a'), ('p2', 'b')]) {
        await send(PlayerJoinedEvent(Player(id: id, name: id, teamId: team)));
      }
      if (setting) await send(const SetCategorySlidesEvent(true));
      await send(const StartRoundEvent('q1'));
    }

    test('teams bet on the category before the question is revealed', () async {
      await start(setting: true);
      final poker = game().poker!;
      expect(poker.questionHidden, isTrue);
      expect(poker.stakesBeforeReveal, isTrue);
      expect(poker.acceptsStakes, isTrue);
      expect(poker.category, 'Deutschland');
      expect(game().activeSlide?.id, 's1');

      // Guests know neither the question nor its media, only the category
      // and its slide.
      final guests = game().redactedForPlayers();
      expect(guests.round.question, isNull);
      expect(guests.activeSlide?.id, 's1');
      final visible = visibleGuestMedia(game());
      expect(visible, contains(flag));
      expect(visible, isNot(contains(questionPicture)));

      // Players address the round by its start, not by the hidden question.
      final startedAt = guests.round.startedAtHostMicros;
      for (final player in ['p1', 'p2']) {
        await send(
          PlacePokerWagerEvent(
            playerId: player,
            roundStartedAt: startedAt,
            wager: 3,
          ),
        );
      }
      expect(game().poker!.wagers, {'a': 3, 'b': 3});
      expect(game().poker!.allStakesIn(teams.keys), isTrue);

      // Closing the betting reveals the question and opens the answers.
      await send(const OpenPokerAnswersEvent());
      expect(game().poker!.betting, isFalse);
      expect(game().poker!.questionHidden, isFalse);
      expect(game().activeSlide, isNull);
      expect(game().redactedForPlayers().round.question?.id, 'q1');
      expect(visibleGuestMedia(game()), contains(questionPicture));
    });

    test('without a slide the question is visible while betting', () async {
      engine = QuizEngineBloc(
        questionBank: [germany, loose],
        slides: [categorySlide],
        teams: teams,
        mode: const TeamMode(),
        pokerStartingChips: 10,
      );
      addTearDown(engine.close);
      await send(const SetCategorySlidesEvent(true));
      await send(const StartRoundEvent('q2'));
      expect(game().poker!.questionHidden, isFalse);
      expect(game().poker!.stakesBeforeReveal, isFalse);
    });

    test(
      'the category phase of jokers shows the slide of the category',
      () async {
        await start(setting: false, jokers: const [ForcedStakeJoker()]);
        final poker = game().poker!;
        expect(poker.questionHidden, isTrue);
        expect(poker.stakesBeforeReveal, isFalse);
        // No stakes before the reveal without the setting.
        expect(poker.acceptsStakes, isFalse);
        expect(game().activeSlide?.id, 's1');
        await send(
          PlacePokerWagerEvent(
            playerId: 'p1',
            roundStartedAt: game().round.startedAtHostMicros,
            wager: 3,
          ),
        );
        expect(game().poker!.wagers, isEmpty);
        await send(const RevealPokerQuestionEvent());
        expect(game().poker!.questionHidden, isFalse);
        expect(game().activeSlide, isNull);
      },
    );
  });
}
