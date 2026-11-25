import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/game_sections.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout.dart';
import 'package:quizmo/presentation/quizmaster/tv_preview_panel.dart';
import 'package:quizmo/presentation/spectator/tv_page.dart';

final _picture = ImageAttachment(
  asset: MediaAsset.upload(
    Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="9">'
        '<rect width="16" height="9" fill="red"/></svg>',
      ),
    ),
    'svg',
  ),
);

final _question = MultipleChoiceQuestion(
  id: 'q',
  prompt: 'Which city?',
  options: const [
    AnswerOption(id: 'a', label: 'Berlin'),
    AnswerOption(id: 'b', label: 'Paris'),
  ],
  correctOptionId: 'a',
  adminNotes: 'Secret note',
  timeLimit: Duration.zero,
  media: [
    _picture,
    const VideoAttachment(youtubeId: 'dQw4w9WgXcQ'),
  ],
);

void main() {
  test('the section is optional, hidden by default and old layouts load', () {
    expect(DashboardSection.tvPreview.required, isFalse);
    final layout = DashboardLayout.standard();
    expect(layout[DashboardSection.tvPreview].isVisible, isFalse);
    final order = [for (final entry in layout.sections) entry.section];
    expect(
      order.indexOf(DashboardSection.tvPreview),
      order.indexOf(DashboardSection.corrections) + 1,
    );
    // A layout saved before the section existed gets it, hidden.
    final old = DashboardLayout.decode(
      jsonEncode({
        'sections': [
          for (final section in DashboardSection.values)
            if (section != DashboardSection.tvPreview)
              {'id': section.name, 'visible': true},
        ],
      }),
    );
    expect(old[DashboardSection.tvPreview].isVisible, isFalse);
    final shown = old.update(
      old[DashboardSection.tvPreview].copyWith(visible: true),
    );
    expect(
      DashboardLayout.decode(
        shown.encode(),
      )[DashboardSection.tvPreview].isVisible,
      isTrue,
    );
  });

  Future<void> show(WidgetTester tester, GameState game, {Uri? join}) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TvPreviewPanel(game: game, quizName: 'Quiz', joinUri: join),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows what the TV shows, never more', (tester) async {
    final game = GameState(
      isStarted: true,
      questionBank: [_question],
      round: RoundState(
        question: _question,
        status: RoundStatus.acceptingAnswers,
        startedAtHostMicros: 1,
      ),
    );
    await show(tester, game);
    expect(find.byType(TvScreen), findsOneWidget);
    expect(find.text('Which city?'), findsOneWidget);
    expect(find.text('Secret note'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    // Video stays a picture: no player, no sound.
    expect(find.byKey(const ValueKey('still-player')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-image')), findsOneWidget);
    final size = tester.getSize(find.byKey(const ValueKey('tv-preview')));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cannot be operated and opens larger', (tester) async {
    await show(tester, const GameState());
    final ignore = find.ancestor(
      of: find.byType(TvScreen),
      matching: find.byType(IgnorePointer),
    );
    expect(
      tester.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('tv-preview-enlarge')));
    await tester.pumpAndSettle();
    expect(find.byType(TvScreen), findsNWidgets(2));
  });

  testWidgets('without a server there is no QR code', (tester) async {
    await show(tester, const GameState());
    expect(find.byKey(const ValueKey('tv-no-server')), findsOneWidget);
    await show(
      tester,
      const GameState(),
      join: Uri.parse('http://192.168.1.2:8080'),
    );
    expect(find.byKey(const ValueKey('tv-no-server')), findsNothing);
  });

  testWidgets('dashboard and preview get the same section', (tester) async {
    final engine = QuizEngineBloc(questionBank: [_question]);
    addTearDown(engine.close);
    late Map<DashboardSection, Widget> sections;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            sections = buildGameSections(
              context,
              engine: engine,
              engineState: engine.state,
              quizName: 'Quiz',
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(sections[DashboardSection.tvPreview], isA<TvPreviewPanel>());
  });
}
