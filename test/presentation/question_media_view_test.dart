import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/common/question_media_view.dart';

void main() {
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
