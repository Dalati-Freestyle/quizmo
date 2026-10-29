import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';

void main() {
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
