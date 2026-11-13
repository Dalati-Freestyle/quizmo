import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/guest_wifi_cubit.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout_settings_page.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_layout_store.dart';
import 'package:quizmo/presentation/quizmaster/layout/dashboard_section_view.dart';
import 'package:quizmo/presentation/quizmaster/wifi/guest_wifi_store.dart';
import 'package:quizmo/presentation/quizmaster/wifi/guest_wifi_toggle.dart';

class _MemoryBackend implements DashboardLayoutBackend {
  _MemoryBackend([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class _MemoryWifiStore extends GuestWifiStore {
  _MemoryWifiStore(this.settings);
  GuestWifiSettings settings;

  @override
  Future<GuestWifiSettings> load() async => settings;

  @override
  Future<void> save(GuestWifiSettings value) async => settings = value;
}

void main() {
  group('DashboardLayout', () {
    test('the standard layout colours every section differently', () {
      final layout = DashboardLayout.standard();
      expect(layout.sections, hasLength(DashboardSection.values.length));
      expect(
        layout.sections.map((s) => s.colorIndex).toSet(),
        hasLength(DashboardSection.values.length),
      );
      expect(
        kDashboardPalette.length,
        greaterThanOrEqualTo(layout.sections.length),
      );
      expect(layout[DashboardSection.serverLog].isVisible, isFalse);
      expect(layout[DashboardSection.serverLog].expanded, isFalse);
      expect(layout[DashboardSection.liveRound].isVisible, isTrue);
    });

    test('missing or broken stored layouts fall back to the standard', () {
      for (final source in [null, '', 'nonsense', '{"sections": 3}', '[]']) {
        expect(DashboardLayout.decode(source), DashboardLayout.standard());
      }
    });

    test('round trips and keeps customisations', () {
      final layout = DashboardLayout.standard()
          .move(0, 5)
          .withColor(3)
          .update(
            DashboardLayout.standard()[DashboardSection.scoreboard].copyWith(
              visible: false,
              expanded: false,
              colorIndex: 9,
            ),
          );
      final restored = DashboardLayout.decode(layout.encode());
      expect(restored, layout);
      expect(restored[DashboardSection.scoreboard].isVisible, isFalse);
      expect(restored[DashboardSection.scoreboard].colorIndex, 9);
      expect(restored.sections[5].section, DashboardSection.sessionAccess);
    });

    test('sections from a later version appear with their defaults', () {
      const stored =
          '{"version":1,"sections":['
          '{"id":"players","color":2,"visible":false,"expanded":true},'
          '{"id":"futureSection","color":1},'
          '{"id":"liveRound","color":99,"visible":"yes"}]}';
      final layout = DashboardLayout.decode(stored);
      expect(layout.sections, hasLength(DashboardSection.values.length));
      expect(layout[DashboardSection.players].colorIndex, 2);
      final live = layout[DashboardSection.liveRound];
      expect(
        live.colorIndex,
        DashboardLayout.standard()[DashboardSection.liveRound].colorIndex,
      );
      expect(live.visible, isTrue);
      expect(layout[DashboardSection.serverLog].isVisible, isFalse);
    });

    test('required sections can never be hidden', () {
      final hidden = DashboardLayout.standard()[DashboardSection.liveRound]
          .copyWith(visible: false);
      expect(hidden.isVisible, isTrue);
      expect(DashboardSection.serverLog.required, isFalse);
      expect(DashboardSection.questions.required, isTrue);
      expect(DashboardSection.players.required, isTrue);
      expect(DashboardSection.sessionAccess.required, isTrue);
    });

    test('an exported file imports, other files are rejected', () {
      final layout = DashboardLayout.standard().withColor(5).move(2, 0);
      expect(DashboardLayout.parseFile(layout.encode()), layout);
      for (final source in ['nonsense', '[]', '{"sections": []}']) {
        expect(() => DashboardLayout.parseFile(source), throwsFormatException);
      }
    });
  });

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Scaffold(body: child),
  );

  testWidgets('sections collapse and expand and follow the stored layout', (
    tester,
  ) async {
    final backend = _MemoryBackend(
      DashboardLayout.standard()
          .update(
            DashboardLayout.standard()[DashboardSection.corrections].copyWith(
              visible: false,
            ),
          )
          .encode(),
    );
    DashboardLayoutStore.useBackend(backend);
    await tester.pumpWidget(
      app(
        const DashboardSectionGrid(
          sections: {
            DashboardSection.liveRound: Text('live panel'),
            DashboardSection.corrections: Text('corrections panel'),
            DashboardSection.serverLog: Text('log panel'),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('live panel'), findsOneWidget);
    expect(find.text('corrections panel'), findsNothing);
    expect(find.text('log panel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dashboard-section-liveRound')));
    await tester.pump();
    expect(find.text('live panel'), findsNothing);
    // The collapsed state is remembered on the device.
    expect(
      DashboardLayout.decode(
        backend.value,
      )[DashboardSection.liveRound].expanded,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('dashboard-section-liveRound')));
    await tester.pump();
    expect(find.text('live panel'), findsOneWidget);
  });

  testWidgets('the settings screen edits visibility, colour and resets', (
    tester,
  ) async {
    final backend = _MemoryBackend();
    DashboardLayoutStore.useBackend(backend);
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: DashboardLayoutSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    final store = DashboardLayoutStore.instance;

    final liveSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey('layout-visible-liveRound')),
    );
    expect(liveSwitch.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('layout-visible-serverLog')));
    await tester.pumpAndSettle();
    expect(store.layout.value[DashboardSection.serverLog].isVisible, isTrue);
    expect(DashboardLayout.decode(backend.value), store.layout.value);

    await tester.tap(find.byKey(const ValueKey('layout-same-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-4')));
    await tester.pumpAndSettle();
    expect(store.layout.value.sections.every((s) => s.colorIndex == 4), isTrue);

    await tester.tap(find.byKey(const ValueKey('layout-reset')));
    await tester.pumpAndSettle();
    expect(store.layout.value, DashboardLayout.standard());
  });

  testWidgets('the settings screen exports and imports layouts', (
    tester,
  ) async {
    DashboardLayoutStore.useBackend(_MemoryBackend());
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? exported;
    var picked = 'not a layout';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: DashboardLayoutSettingsPage(
            saveLayoutFile: (contents) async {
              exported = contents;
              return true;
            },
            pickLayoutFile: () async => picked,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final store = DashboardLayoutStore.instance;
    await tester.tap(find.byKey(const ValueKey('layout-export')));
    await tester.pumpAndSettle();
    expect(DashboardLayout.parseFile(exported!), store.layout.value);

    await tester.tap(find.byKey(const ValueKey('layout-import')));
    await tester.pumpAndSettle();
    expect(find.text('The file is not valid JSON.'), findsOneWidget);
    expect(store.layout.value, DashboardLayout.standard());

    final custom = DashboardLayout.standard().withColor(7);
    picked = custom.encode();
    await tester.tap(find.byKey(const ValueKey('layout-import')));
    await tester.pumpAndSettle();
    expect(store.layout.value, custom);
  });

  testWidgets('the admin view only switches the stored guest Wi-Fi', (
    tester,
  ) async {
    const wifi = GuestWifi(ssid: 'Quiz Night', password: 'correct horse');
    final cubit = GuestWifiCubit();
    addTearDown(cubit.close);
    final store = _MemoryWifiStore(
      const GuestWifiSettings().remember(wifi, showOnTv: false),
    );
    await tester.pumpWidget(
      app(
        GuestWifiToggle(
          guestWifi: cubit,
          store: store,
          currentNetwork: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Network: Quiz Night'), findsOneWidget);
    expect(cubit.state, isNull);
    await tester.tap(find.byKey(const ValueKey('guest-wifi-toggle')));
    await tester.pumpAndSettle();
    expect(cubit.state, wifi);
    expect(store.settings.showOnTv, isTrue);
    await tester.tap(find.byKey(const ValueKey('guest-wifi-toggle')));
    await tester.pumpAndSettle();
    expect(cubit.state, isNull);
    expect(store.settings.networks, [wifi]);
  });

  testWidgets('without a stored network the switch is disabled', (
    tester,
  ) async {
    final cubit = GuestWifiCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      app(
        GuestWifiToggle(
          guestWifi: cubit,
          store: _MemoryWifiStore(const GuestWifiSettings()),
          currentNetwork: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('guest-wifi-toggle')),
    );
    expect(toggle.onChanged, isNull);
  });
}
