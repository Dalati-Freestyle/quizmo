import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/settings/media_preload_settings.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    MediaPreloadSettings.useSettings(MediaPreloadSettings());
  });

  testWidgets('players can limit preloading by size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MediaPreloadSwitch())),
    );
    await tester.pumpAndSettle();
    final settings = MediaPreloadSettings.instance;
    expect(settings.maxBytes, isNull);
    await tester.tap(find.byKey(const ValueKey('settings-preload-limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('250 MB').last);
    await tester.pumpAndSettle();
    expect(settings.maxBytes, 250 * 1000 * 1000);

    // The choice survives a restart of the app.
    final restarted = MediaPreloadSettings();
    await restarted.load();
    expect(restarted.maxMegabytes.value, 250);

    // Without preloading the limit is not offered.
    await tester.tap(find.byKey(const ValueKey('settings-preload-media')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-preload-limit')), findsNothing);
  });
}
