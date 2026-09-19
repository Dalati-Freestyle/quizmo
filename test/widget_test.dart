/// Smoke test of the application shell.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/common/role_selection_page.dart';
import 'package:quizmo/presentation/player/player_page.dart';

void main() {
  testWidgets('starts on the role selection screen', (tester) async {
    await tester.pumpWidget(const QuizmoApp());

    expect(find.byType(RoleSelectionPage), findsOneWidget);
    expect(find.text('Quizmo'), findsOneWidget);
    expect(find.text('Host a quiz'), findsOneWidget);
    expect(find.text('Join as player'), findsOneWidget);
  });

  testWidgets('opens the player join form', (tester) async {
    await tester.pumpWidget(const QuizmoApp());

    await tester.tap(find.text('Open player view'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('Host address'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
  });

  testWidgets('rejects an incomplete join form', (tester) async {
    await tester.pumpWidget(const QuizmoApp());
    await tester.tap(find.text('Open player view'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect and sync clock'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a name'), findsOneWidget);
  });
}

