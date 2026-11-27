import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:quizmo/core/data/game_protocol_builder.dart';
import 'package:quizmo/core/data/quiz_import_export.dart';
import 'package:quizmo/core/data/session_report.dart';
import 'package:quizmo/core/engine/geo.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/engine/tech_check.dart';
import 'package:quizmo/core/models/media_aspect.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/place_search.dart';
import 'package:quizmo/core/simulation/bot_decisions.dart';

const eiffel = GeoPoint(48.8584, 2.2945);

LocationQuestion question({
  GeoPoint? target = eiffel,
  double full = 5,
  double zero = 805,
}) => LocationQuestion(
  id: 'q',
  prompt: 'Wo?',
  target: target,
  targetLabel: 'Eiffelturm',
  fullPointsKm: full,
  zeroPointsKm: zero,
  timeLimit: Duration.zero,
);

LocationAnswer guess(
  double latitude,
  double longitude, {
  String player = 'p',
}) => LocationAnswer(
  playerId: player,
  questionId: 'q',
  clientTimestampMicros: 0,
  clockOffsetMicros: 0,
  latitude: latitude,
  longitude: longitude,
);

void main() {
  group('distance', () {
    test('matches known great-circle distances', () {
      // Paris – Berlin, about 878 km.
      expect(distanceKm(48.8566, 2.3522, 52.52, 13.405), closeTo(878, 3));
      expect(distanceKm(10, 20, 10, 20), 0);
      // Across the date line: 2 degrees of longitude at the equator.
      expect(distanceKm(0, 179, 0, -179), closeTo(222.4, 0.5));
      // Near the poles everything is close.
      expect(distanceKm(89.9, 0, 89.9, 180), closeTo(22.2, 0.5));
      expect(distanceKm(90, 0, -90, 0), closeTo(maxDistanceKm, 1e-6));
    });

    test('full points, none and a monotone slope in between', () {
      final q = question();
      expect(q.accuracy(guess(eiffel.latitude, eiffel.longitude)), 1);
      // About 4.4 km away: still full.
      expect(q.accuracy(guess(48.8584, 2.3545)), 1);
      // Berlin (≈ 880 km): beyond the zero radius.
      expect(q.accuracy(guess(52.52, 13.405)), 0);
      var last = 1.0;
      for (var degrees = 0.1; degrees < 8; degrees += 0.1) {
        final share = q.accuracy(guess(48.8584 + degrees, 2.2945));
        expect(share, lessThanOrEqualTo(last));
        if (distanceKm(48.8584 + degrees, 2.2945, 48.8584, 2.2945) > 5) {
          expect(share, lessThan(1));
        }
        last = share;
      }
      expect(locationAccuracy(405, 5, 805), closeTo(0.5, 1e-9));
    });

    test('formats distances for people', () {
      expect(formatDistance(0.42), '420 m');
      expect(formatDistance(3.456), '3.5 km');
      expect(formatDistance(123.4), '123 km');
    });
  });

  test('validation of target and radii', () {
    expect(question().contentErrors, isEmpty);
    expect(question(target: null).solutionErrors, hasLength(1));
    expect(question(full: 10, zero: 10).structureErrors, hasLength(1));
    expect(question(zero: 30000).structureErrors, hasLength(1));
    expect(question().supportsUniqueness, isFalse);
    expect(question().supportsDrafts, isTrue);
  });

  test('the place stays secret until the reveal', () {
    final redacted = question().redacted();
    expect(redacted.target, isNull);
    expect(redacted.targetLabel, isEmpty);
    final wire = jsonEncode(question().forWire(reveal: false).toJson());
    expect(wire, isNot(contains('48.8584')));
    expect(wire, isNot(contains('Eiffelturm')));
    expect(question().forWire(reveal: true), question());
    expect(question().solutionLabel, 'Eiffelturm (48.85840, 2.29450)');
  });

  test('bots hit or miss reliably', () {
    for (final target in [
      eiffel,
      const GeoPoint(-33.86, 151.21),
      const GeoPoint(0, -179.5),
    ]) {
      final q = question(target: target, zero: 20000);
      expect(
        q.accuracy(botAnswer(q, playerId: 'b', timestamp: 0, correct: true)),
        1,
      );
      expect(
        q.accuracy(botAnswer(q, playerId: 'b', timestamp: 0, correct: false)),
        0,
      );
    }
  });

  group('in a game', () {
    Future<QuizEngineBloc> play({
      int? poker,
      List<LocationAnswer> answers = const [],
    }) async {
      final engine = QuizEngineBloc(
        questionBank: [question()],
        teams: const {
          'a': Team(id: 'a', name: 'A'),
          'b': Team(id: 'b', name: 'B'),
        },
        mode: const TeamMode(),
        pokerStartingChips: poker,
      );
      addTearDown(engine.close);
      engine
        ..add(
          const PlayerJoinedEvent(Player(id: 'pa', name: 'Ada', teamId: 'a')),
        )
        ..add(
          const PlayerJoinedEvent(Player(id: 'pb', name: 'Bo', teamId: 'b')),
        )
        ..add(const StartRoundEvent('q'));
      await pumpEventQueue();
      if (poker != null) {
        for (final id in ['pa', 'pb']) {
          engine.add(
            PlacePokerWagerEvent(playerId: id, questionId: 'q', wager: 20),
          );
        }
        engine.add(const OpenPokerAnswersEvent());
        await pumpEventQueue();
      }
      for (final answer in answers) {
        engine.add(SubmitAnswerEvent(answer));
      }
      await pumpEventQueue();
      engine.add(const RevealRoundEvent());
      await pumpEventQueue();
      return engine;
    }

    test('scores by distance; report, CSV and protocol name it', () async {
      final engine = await play(
        answers: [
          guess(48.8584, 2.2945, player: 'pa'),
          guess(50.8584, 2.2945, player: 'pb'),
        ],
      );
      final game = engine.state.game;
      expect(game.teamScores['a'], 10);
      expect(game.teamScores['b'], inExclusiveRange(0, 10));
      final report = SessionReport.fromGame(game, title: 'x');
      expect(report.toCsv(), contains('km'));
      final protocol = buildGameProtocol(game, title: 'x');
      expect(
        protocol.questions.single.answers.map((a) => a.answer).join(),
        contains('km'),
      );
      expect(guestSnapshotOf(game, title: 'x').round.answers, hasLength(2));
    });

    test('poker only pays a mark within the full radius', () async {
      final engine = await play(
        poker: 100,
        answers: [
          guess(48.86, 2.30, player: 'pa'),
          guess(49.2, 2.2945, player: 'pb'),
        ],
      );
      expect(engine.state.game.poker!.chips, {'a': 120, 'b': 80});
    });

    test('a marker that was not confirmed counts like a draft', () async {
      final engine = QuizEngineBloc(questionBank: [question()]);
      addTearDown(engine.close);
      engine
        ..add(const PlayerJoinedEvent(Player(id: 'p', name: 'P')))
        ..add(const StartRoundEvent('q'));
      await pumpEventQueue();
      engine.add(
        UpdateDraftEvent(
          AnswerDraft(
            playerId: 'p',
            questionId: 'q',
            roundStartedAt: engine.state.game.round.startedAtHostMicros!,
            clientTimestampMicros: engine.state.game.round.startedAtHostMicros!,
            clockOffsetMicros: 0,
            content: guess(48.8584, 2.2945),
          ),
        ),
      );
      engine.add(const RevealRoundEvent());
      await pumpEventQueue();
      expect(engine.state.game.round.adoptedPlayerIds, {'p'});
      expect(engine.state.game.scores.scoreOf('p'), 10);
    });
  });

  test('a snowflake quiz does not offer the kind', () {
    final quiz = Quiz(
      id: 'q',
      name: 'Q',
      description: 'D',
      category: 'C',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      format: const SnowflakeFormat(),
      questions: [question().withoutSolution()],
    );
    expect(quiz.validationErrors(), isNotEmpty);
  });

  test('the tech check knows the map needs internet', () {
    expect(checkQuizMedia([question()]).online, hasLength(1));
  });

  group('files', () {
    final source = File(
      p.join('test', 'fixtures', 'quiz_v15_with_media.quizmo.json'),
    ).readAsStringSync();

    test('schema 15 imports and may not contain map questions', () {
      final quiz = parseQuizImport(source);
      expect(quiz.schemaVersion, Quiz.currentSchemaVersion);
      expect(quiz.questions.first.prompt, startsWith('**Fett**'));
      expect(parseQuizImport(exportQuizJson(quiz)).questions, quiz.questions);
      final json = jsonDecode(source) as JsonMap;
      (json['questions'] as List).add(question().toJson());
      expect(() => Quiz.fromJson(json), throwsA(isA<JsonContractException>()));
      final current = Quiz.fromJson({...json, 'schemaVersion': 16});
      expect(current.questions.last, question());
      expect(
        parseQuizImport(exportQuizJson(current)).questions.last,
        question(),
      );
    });

    test('a saved game with a map round comes back', () {
      final round = RoundState(
        question: question(),
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: 1,
        answers: {'p': guess(1, 2)},
      );
      expect(
        RoundState.fromJson(jsonDecode(jsonEncode(round.toJson()))),
        round,
      );
    });
  });

  test('photos with GPS data are recognised', () {
    final gps = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE1, 0, 24, ...ascii.encode('Exif'), 0, 0, //
      0x49, 0x49, 42, 0, 8, 0, 0, 0, 1, 0, 0x25, 0x88, 4, 0, 1, 0, 0, 0, //
      0, 0, 0, 0, 0xFF, 0xD9,
    ]);
    expect(hasGpsMetadata(gps), isTrue);
    expect(
      hasGpsMetadata(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])),
      isFalse,
    );
  });

  group('place search', () {
    test('lists distinguishable hits and sends only the words', () async {
      Uri? asked;
      final search = NominatimPlaceSearch(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode([
              {
                'name': 'Paris',
                'display_name': 'Paris, Île-de-France, France',
                'lat': '48.85',
                'lon': '2.35',
              },
              {
                'name': 'Paris',
                'display_name': 'Paris, Texas, United States',
                'lat': '33.66',
                'lon': '-95.55',
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final hits = await search.search('Paris');
      expect(hits, hasLength(2));
      expect(hits.map((h) => h.description).toSet(), hasLength(2));
      expect(asked!.queryParameters['q'], 'Paris');
    });

    test('reports errors and empty results understandably', () async {
      for (final (response, message) in [
        (http.Response('[]', 200), null),
        (http.Response('oops', 500), 'nicht verfügbar'),
      ]) {
        final search = NominatimPlaceSearch(
          client: MockClient((_) async => response),
        );
        if (message == null) {
          expect(await search.search('xyz'), isEmpty);
        } else {
          await expectLater(
            search.search('xyz'),
            throwsA(
              isA<PlaceSearchException>().having(
                (e) => e.message,
                'message',
                contains(message),
              ),
            ),
          );
        }
      }
      final offline = NominatimPlaceSearch(
        client: MockClient((_) async => throw const SocketException('down')),
      );
      await expectLater(
        offline.search('x'),
        throwsA(isA<PlaceSearchException>()),
      );
    });
  });
}
