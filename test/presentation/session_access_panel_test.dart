import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/session_access.dart';
import 'package:quizmo/presentation/quizmaster/session_access_panel.dart';

void main() {
  testWidgets('host can configure code, approval, lobby lock and spectators', (
    tester,
  ) async {
    final access = SessionAccess();
    addTearDown(access.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionAccessPanel(access: access),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Lock new joins'));
    await tester.pump();
    expect(access.state.locked, isTrue);
    await tester.tap(find.text('Approve new participants'));
    await tester.pump();
    expect(access.state.requireApproval, isTrue);
    await tester.enterText(find.byType(TextField), 'secret-code');
    await tester.pump();
    await tester.tap(find.text('Set join code'));
    await tester.pump();
    expect(
      access.state.codeHash,
      SessionAccess.digestCredential('secret-code'),
    );
    expect(find.text('secret-code'), findsNothing);
    await tester.ensureVisible(find.text('Allow spectators'));
    await tester.tap(find.text('Allow spectators'));
    await tester.pump();
    expect(access.state.allowSpectators, isFalse);
    await tester.ensureVisible(find.text('Remove join code'));
    await tester.tap(find.text('Remove join code'));
    await tester.pump();
    expect(access.state.codeHash, isNull);
  });

  testWidgets(
    'host sees waiting names and distinct approval/rejection actions',
    (tester) async {
      final access = SessionAccess();
      addTearDown(access.close);
      access.request('ada', 'Ada');
      access.request('linus', 'Linus');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SessionAccessPanel(access: access),
            ),
          ),
        ),
      );
      expect(find.text('Ada'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Approve').first);
      await tester.tap(find.byTooltip('Approve').first);
      await tester.pump();
      expect(
        access.state.requests['ada']!.decision,
        AdmissionDecision.approved,
      );
      await tester.ensureVisible(find.byTooltip('Reject').last);
      await tester.tap(find.byTooltip('Reject').last);
      await tester.pump();
      expect(
        access.state.requests['linus']!.decision,
        AdmissionDecision.rejected,
      );
      expect(find.text('No pending requests.'), findsOneWidget);
    },
  );
}
