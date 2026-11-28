import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/common/media_volume.dart';

class MemoryVolumeStore extends MediaVolumeStore {
  MemoryVolumeStore([this.stored]);
  ({double level, bool muted})? stored;

  @override
  Future<({double level, bool muted})?> read() async => stored;

  @override
  Future<void> write(double level, bool muted) async =>
      stored = (level: level, muted: muted);
}

void main() {
  test('level and mute are kept in the store', () async {
    final store = MemoryVolumeStore((level: 0.3, muted: true));
    final volume = MediaVolume(store: store);
    addTearDown(volume.dispose);
    expect(volume.effective, 1);
    await volume.load();
    expect((volume.level, volume.muted, volume.effective), (0.3, true, 0.0));
    volume.toggleMute();
    expect(volume.effective, 0.3);
    volume.setLevel(0.8);
    await pumpEventQueue();
    expect(store.stored, (level: 0.8, muted: false));
    volume.setLevel(0);
    volume.toggleMute();
    volume.toggleMute();
    // Unmuting at 0 would stay silent.
    expect(volume.effective, 0.5);
    volume.setLevel(4);
    expect(volume.level, 1);
  });

  testWidgets('the control changes the volume of the scope', (tester) async {
    final volume = MediaVolume();
    addTearDown(volume.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaVolumeScope(
            volume: volume,
            child: const Center(child: MediaVolumeControl()),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('media-mute')));
    await tester.pump();
    expect(volume.muted, isTrue);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    final slider = find.byKey(const ValueKey('media-volume-slider'));
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(40, 24));
    await tester.pump();
    expect(volume.muted, isFalse);
    expect(volume.level, lessThan(0.5));
  });

  testWidgets('without a scope the device volume rules', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MediaVolumeControl())),
    );
    expect(find.byType(Slider), findsNothing);
  });
}
