import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/l10n/app_localizations.dart';
import 'package:quizmo/presentation/quizmaster/editor/media_editor.dart';
import 'package:quizmo/presentation/settings/media_upload_settings.dart';

/// Keeps the choice in memory instead of the platform preferences.
class FakeMediaUploadSettingsStore extends MediaUploadSettingsStore {
  FakeMediaUploadSettingsStore({this.unlimited = false});
  bool unlimited;
  @override
  Future<bool> loadUnlimited() async => unlimited;
  @override
  Future<void> saveUnlimited(bool value) async => unlimited = value;
}

void main() {
  late MediaUploadSettingsStore original;
  setUp(() => original = MediaUploadSettingsStore.instance);
  tearDown(() => MediaUploadSettingsStore.useStore(original));

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  test('the limit is 20 MiB unless unlimited uploads are allowed', () async {
    final store = FakeMediaUploadSettingsStore();
    expect(await store.uploadLimit(), maxMediaBytes);
    await store.saveUnlimited(true);
    expect(await store.uploadLimit(), isNull);
  });

  testWidgets('the switch stores the choice and is off by default', (
    tester,
  ) async {
    final store = FakeMediaUploadSettingsStore();
    MediaUploadSettingsStore.useStore(store);
    await tester.pumpWidget(app(const MediaUploadSettings()));
    await tester.pumpAndSettle();
    expect(find.text('Allow media files of any size'), findsOneWidget);
    final tile = find.byKey(const ValueKey('settings-unlimited-media'));
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(store.unlimited, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('the media editor names the active limit', (tester) async {
    for (final (unlimited, text) in [
      (false, 'maximum 20 MiB'),
      (true, 'no size limit'),
    ]) {
      MediaUploadSettingsStore.useStore(
        FakeMediaUploadSettingsStore(unlimited: unlimited),
      );
      await tester.pumpWidget(
        app(
          MediaEditor(
            key: ValueKey(unlimited),
            media: const [],
            onChanged: (_) {},
            title: 'Media',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(text), findsOneWidget);
    }
  });
}
