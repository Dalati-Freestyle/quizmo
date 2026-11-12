/// Smoke test of the application shell.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/app.dart';
import 'package:quizmo/presentation/common/role_selection_page.dart';
import 'package:quizmo/presentation/player/player_page.dart';

import 'helpers/memory_recovery_store.dart';

void main() {
  testWidgets('starts on the role selection screen', (tester) async {
    await tester.pumpWidget(QuizmoApp(recoveryStore: MemoryRecoveryStore()));
    await tester.pumpAndSettle();

    expect(find.byType(RoleSelectionPage), findsOneWidget);
    expect(find.text('Quizmo'), findsOneWidget);
    expect(find.text('Host a quiz'), findsOneWidget);
    expect(find.text('Join as player'), findsOneWidget);
  });

  testWidgets('opens the player join form', (tester) async {
    await tester.pumpWidget(QuizmoApp(recoveryStore: MemoryRecoveryStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open player view'));
    await _pumpPlayerPage(tester);

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('Host address'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
  });

  testWidgets('rejects an incomplete join form', (tester) async {
    await tester.pumpWidget(QuizmoApp(recoveryStore: MemoryRecoveryStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open player view'));
    await _pumpPlayerPage(tester);

    // The LAN list above can push the button below the 800×600 test view.
    await tester.ensureVisible(find.text('Continue to team selection'));
    await tester.pump();
    await tester.tap(find.text('Continue to team selection'));
    await _pumpPlayerPage(tester);

    expect(find.text('Pick a name'), findsOneWidget);
  });
}

/// Lets the route transition finish without waiting for the page to settle.
///
/// The player page starts LAN discovery. Where mDNS is supported (Windows,
/// macOS) the search indicator animates for as long as it browses, so
/// `pumpAndSettle` would time out, while on Linux CI discovery is unsupported
/// and the page settles. Fixed frames keep the test platform independent.
Future<void> _pumpPlayerPage(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
