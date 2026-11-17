import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/settings/locale_cubit.dart';
import 'package:quizmo/presentation/settings/settings_page.dart';

class _MemoryLanguageStore implements LanguagePreferenceStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

void main() {
  Future<void> pump(WidgetTester tester, {required bool host}) async {
    final cubit = LocaleCubit(store: _MemoryLanguageStore());
    addTearDown(cubit.close);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: BlocProvider.value(
          value: cubit,
          child: SettingsPage(
            hostSettings: host,
            loadVersion: () async => (version: '1.3.0', build: '1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hosts get the admin view, guest Wi-Fi and AI guide entries', (
    tester,
  ) async {
    await pump(tester, host: true);
    expect(find.byKey(const ValueKey('settings-admin-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-guest-wifi')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-ai-guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tech-check')), findsOneWidget);
    expect(find.text('Create a quiz with AI'), findsOneWidget);
  });

  testWidgets('players and TVs do not see host settings', (tester) async {
    await pump(tester, host: false);
    expect(find.byKey(const ValueKey('settings-admin-layout')), findsNothing);
    expect(find.byKey(const ValueKey('settings-ai-guide')), findsNothing);
  });
}
