import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/guest_wifi_cubit.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/wifi/guest_wifi_panel.dart';
import 'package:quizmo/presentation/quizmaster/wifi/guest_wifi_store.dart';

class _MemoryStore extends GuestWifiStore {
  _MemoryStore(this.settings);
  GuestWifiSettings settings;

  @override
  Future<GuestWifiSettings> load() async => settings;

  @override
  Future<void> save(GuestWifiSettings value) async => settings = value;
}

void main() {
  const saved = GuestWifi(ssid: 'Quiz Night', password: 'correct horse');

  Future<void> pump(WidgetTester tester, Widget panel) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(body: SingleChildScrollView(child: panel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('restores the saved network and shows it on the TV again', (
    tester,
  ) async {
    final cubit = GuestWifiCubit();
    addTearDown(cubit.close);
    final store = _MemoryStore(
      const GuestWifiSettings().remember(saved, showOnTv: true),
    );
    await pump(
      tester,
      GuestWifiPanel(
        guestWifi: cubit,
        store: store,
        currentNetwork: () async => null,
      ),
    );

    expect(cubit.state, saved);
    expect(find.text('Quiz Night'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(cubit.state, isNull);
    expect(store.settings.showOnTv, isFalse);
    expect(store.settings.networks, [saved]);
  });

  testWidgets('saving a new network stores it and puts it on the TV', (
    tester,
  ) async {
    final cubit = GuestWifiCubit();
    addTearDown(cubit.close);
    final store = _MemoryStore(const GuestWifiSettings());
    await pump(
      tester,
      GuestWifiPanel(
        guestWifi: cubit,
        store: store,
        currentNetwork: () async => null,
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'Guests');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.pump();
    expect(find.text('A WPA password has 8 to 63 characters.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'long enough');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    const expected = GuestWifi(ssid: 'Guests', password: 'long enough');
    expect(cubit.state, expected);
    expect(store.settings.networks, [expected]);
    expect(store.settings.showOnTv, isTrue);
  });
}
