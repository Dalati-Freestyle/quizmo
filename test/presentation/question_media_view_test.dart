import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';

void main() {
  testWidgets('preload errors remain interactive; retry and room cache work', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<rect width="10" height="10" fill="red"/></svg>',
      ),
    );
    final asset = MediaAsset.upload(bytes, 'svg');
    final reference = ImageAttachment(
      asset: MediaAsset(id: asset.id, mimeType: asset.mimeType),
      caption: 'Visible image',
      zoom: false,
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        Widget view(String room, {bool show = true}) => MaterialApp(
          home: Scaffold(
            body: SessionMediaAccess(
              baseUri: Uri.parse('https://host/rooms/$room?access=token-$room'),
              child: Column(
                children: [
                  const TextButton(
                    onPressed: null,
                    child: Text('Other controls'),
                  ),
                  QuestionMediaView(media: show ? [reference] : []),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(view('first'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.text('Other controls'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();
        expect(find.text('Visible image'), findsOneWidget);
        expect(requests, 2);
        await tester.pumpWidget(view('first', show: false));
        await tester.pumpWidget(view('first'));
        await tester.pumpAndSettle();
        expect(requests, 2);
        await tester.pumpWidget(view('second'));
        await tester.pumpAndSettle();
        expect(requests, 3);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient(
        (_) async => ++requests == 1
            ? http.Response('Temporarily unavailable', 503)
            : http.Response.bytes(bytes, 200),
      ),
    );
  });

  testWidgets('slow media shows progress without blocking controls', (
    tester,
  ) async {
    final chunks = StreamController<List<int>>();
    var tapped = false;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SessionMediaAccess(
                baseUri: Uri.parse('https://host/rooms/first'),
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () => tapped = true,
                      child: const Text('Answer'),
                    ),
                    QuestionMediaView(
                      media: [
                        ImageAttachment(
                          asset: MediaAsset(
                            id: 'a' * 64,
                            mimeType: 'image/png',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        chunks.add([1, 2, 3]);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        await tester.tap(find.text('Answer'));
        expect(tapped, isTrue);
        await tester.pump(const Duration(seconds: 31));
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await chunks.close();
      },
      () => MockClient.streaming(
        (_, _) async =>
            http.StreamedResponse(chunks.stream, 200, contentLength: 100),
      ),
    );
  });

  test('remote media keeps its read capability without changing the route', () {
    final asset = MediaAsset(id: 'a' * 64, mimeType: 'image/png');
    final view = QuestionMediaView(
      media: const [],
      baseUri: Uri.parse(
        'http://host:8080?session=game&access=private-read-token',
      ),
    );
    final source = view.source(asset);
    expect(source.path, '/api/media/${asset.id}');
    expect(source.host, 'host');
    expect(source.queryParameters, {'access': 'private-read-token'});
  });

  testWidgets(
    'TV media inherits its authenticated host rather than using the page origin',
    (tester) async {
      Uri? source;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionMediaAccess(
            baseUri: Uri.parse('http://host:8080?access=private-tv-token'),
            child: Builder(
              builder: (context) {
                source = const QuestionMediaView(media: []).source(
                  MediaAsset(id: 'a' * 64, mimeType: 'image/png'),
                  context,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(source!.host, 'host');
      expect(source!.queryParameters['access'], 'private-tv-token');
    },
  );

  testWidgets(
    'YouTube opens in a browser on desktop',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuestionMediaView(
              media: [VideoAttachment(youtubeId: 'dQw4w9WgXcQ')],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}
