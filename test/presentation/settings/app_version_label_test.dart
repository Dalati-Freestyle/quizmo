import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/settings/app_version_label.dart';

void main() {
  Future<void> pump(WidgetTester tester, AppVersionLoader load) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(body: AppVersionLabel(load: load)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows version and build number', (tester) async {
    await pump(tester, () async => (version: '1.2.0', build: '19'));
    expect(find.text('Version 1.2.0 (build 19)'), findsOneWidget);
  });

  testWidgets('omits an empty build number', (tester) async {
    await pump(tester, () async => (version: '1.2.0', build: ''));
    expect(find.text('Version 1.2.0'), findsOneWidget);
  });

  testWidgets('a failing lookup does not break the settings', (tester) async {
    await pump(tester, () => Future.error(StateError('no version.json')));
    expect(find.text('Version unknown'), findsOneWidget);
  });
}
