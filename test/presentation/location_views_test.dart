import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/place_search.dart';
import 'package:quizmo/core/net/quiz_client.dart';
import 'package:quizmo/presentation/common/location_map.dart';
import 'package:quizmo/presentation/player/questions/new_question_views.dart';
import 'package:quizmo/presentation/quizmaster/editor/location_question_fields.dart';
import 'package:quizmo/presentation/spectator/spectator_session_cubit.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

const _question = LocationQuestion(
  id: 'q',
  prompt: 'Wo steht der Eiffelturm?',
  target: GeoPoint(48.8584, 2.2945),
  targetLabel: 'Eiffelturm',
  timeLimit: Duration.zero,
);

class _FakeSearch implements PlaceSearch {
  @override
  Future<List<PlaceHit>> search(String query, {String? language}) async => [
    const PlaceHit(
      name: 'Eiffelturm',
      description: 'Eiffelturm, Paris, Frankreich',
      latitude: 48.8584,
      longitude: 2.2945,
    ),
  ];
}

void main() {
  Future<void> tapMap(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    // The map waits whether a double tap (zoom) follows.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a tap marks, only the button sends', (tester) async {
    GeoPoint? sent;
    GeoPoint? draft;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationQuestionView(
              question: _question.redacted(),
              enabled: true,
              onSubmit: (point) => sent = point,
              onChanged: (point) => draft = point,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Markierung bestätigen');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tapMap(tester);
    expect(draft, isNotNull);
    expect(sent, isNull, reason: 'a tap alone never answers');
    await tester.tap(button);
    expect(sent, draft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor sets the place by search, marker and numbers', (
    tester,
  ) async {
    Map<String, Object?>? fields;
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationQuestionFields(
              question: const LocationQuestion(id: 'q', prompt: ''),
              search: _FakeSearch(),
              onChanged: (value) => fields = value,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('place-search')),
      'Eiffel',
    );
    await tester.tap(find.byKey(const ValueKey('place-search-button')));
    await tester.pumpAndSettle();
    expect(find.text('Eiffelturm, Paris, Frankreich'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('place-hit-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('target-latitude')))
          .controller!
          .text,
      startsWith('48.8584'),
    );
    expect(fields!['targetLabel'], 'Eiffelturm');
    final question = LocationQuestion.fromJson({
      ...const LocationQuestion(id: 'q', prompt: 'P').toJson(),
      ...fields!,
    });
    expect(question.contentErrors, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('target-latitude')), '10');
    await tester.enterText(
      find.byKey(const ValueKey('target-longitude')),
      '20',
    );
    await tester.pump();
    expect(fields!['target'], {'latitude': 10.0, 'longitude': 20.0});
    final pin = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(pin.markers.single.point, const LatLng(10, 20));

    await tester.enterText(find.byKey(const ValueKey('zero-points-km')), '1');
    await tester.pump();
    expect(
      LocationQuestion.fromJson({
        ...const LocationQuestion(id: 'q', prompt: 'P').toJson(),
        ...fields!,
      }).structureErrors,
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV and player show the place, every guess and the distances', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = GameState(
      isStarted: true,
      players: {
        for (var i = 0; i < 12; i++)
          'p$i': Player(id: 'p$i', name: 'Spieler $i'),
      },
      round: RoundState(
        question: _question,
        status: RoundStatus.revealed,
        startedAtHostMicros: 1,
        answers: {
          for (var i = 0; i < 12; i++)
            'p$i': LocationAnswer(
              playerId: 'p$i',
              questionId: 'q',
              clientTimestampMicros: 2,
              clockOffsetMicros: 0,
              latitude: 48.8 + i * 0.001,
              longitude: 2.29,
            ),
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvScreen(
            state: SpectatorSessionState(
              status: QuizClientStatus.connected,
              game: game,
            ),
            joinUri: Uri.parse('http://localhost:8080'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LocationResultView), findsOneWidget);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(13),
    );
    expect(find.textContaining('1. Spieler'), findsOneWidget);
    expect(find.text('… und 4 weitere'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
