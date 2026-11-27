import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/quiz_engine_bloc.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/core/net/media_preloader.dart';
import 'package:quizmo/presentation/common/media_preload_view.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';
import 'package:quizmo/presentation/quizmaster/media_preload_status_view.dart';

void main() {
  const manifest = MediaPreloadManifest(
    items: [
      MediaPreloadItem(handle: 'a', size: 2000000),
      MediaPreloadItem(handle: 'b', size: 3000000),
    ],
    onlineCount: 1,
  );

  testWidgets('a device shows its progress and the online media', (
    tester,
  ) async {
    final preloader = MediaPreloader()..setEnabled(false);
    addTearDown(preloader.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionMediaAccess(
            baseUri: Uri.parse('http://localhost:8080'),
            preloader: preloader,
            child: const MediaPreloadView(),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('media-preload')), findsNothing);
    preloader.offer(manifest, Uri.parse('http://localhost:8080'));
    await tester.pump();
    expect(
      find.text('Vorladen ist aus: Medien laden, wenn eine Frage sie braucht.'),
      findsOneWidget,
    );
    expect(
      find.text('1 Online-Medien (YouTube, Karten) laden erst im Quiz.'),
      findsOneWidget,
    );
  });

  testWidgets('the host sees every device in the lobby', (tester) async {
    MediaAsset svg(String color) => MediaAsset.upload(
      Uint8List.fromList(
        utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg"><rect fill="$color"/></svg>',
        ),
      ),
      'svg',
    );
    final engine = QuizEngineBloc(
      questionBank: [
        TrueFalseQuestion(
          id: 'q',
          prompt: '?',
          media: [ImageAttachment(asset: svg('red'))],
        ),
      ],
    );
    addTearDown(engine.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaPreloadStatusView(engine: engine)),
      ),
    );
    expect(find.text('Noch kein Gerät meldet seinen Stand.'), findsOneWidget);
    engine.mediaPreloadStatuses
      ..report(
        'c1',
        name: 'Ada',
        tv: false,
        status: const MediaPreloadStatus(
          phase: MediaPreloadPhase.loading,
          totalFiles: 1,
          loadedBytes: 40,
          totalBytes: 100,
        ),
      )
      ..report(
        'c2',
        name: 'Bob',
        tv: false,
        status: const MediaPreloadStatus(phase: MediaPreloadPhase.disabled),
      )
      ..report(
        'c3',
        name: 'TV',
        tv: true,
        status: const MediaPreloadStatus(phase: MediaPreloadPhase.done),
      );
    await tester.pump();
    expect(find.text('lädt 40 %'), findsOneWidget);
    expect(find.text('Vorladen deaktiviert'), findsOneWidget);
    expect(find.text('alle Medien geladen'), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);
    engine.mediaPreloadStatuses.remove('c2');
    await tester.pump();
    await tester.pump();
    expect(find.text('Vorladen deaktiviert'), findsNothing);
  });
}
