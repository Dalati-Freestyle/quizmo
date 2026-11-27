/// Volume of the media on one device (the TV), kept between visits.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Stores the volume of this device.
class MediaVolumeStore {
  /// Creates the store.
  MediaVolumeStore();

  static const _levelKey = 'quizmo.tv.volume';
  static const _mutedKey = 'quizmo.tv.muted';

  late final _preferences = SharedPreferencesAsync();

  /// The stored level (0–1) and mute state; `null` when nothing is stored.
  Future<({double level, bool muted})?> read() async {
    try {
      final level = await _preferences.getDouble(_levelKey);
      if (level == null) return null;
      return (
        level: level.clamp(0.0, 1.0),
        muted: await _preferences.getBool(_mutedKey) ?? false,
      );
    } on Object {
      return null;
    }
  }

  /// Stores [level] and [muted].
  Future<void> write(double level, bool muted) async {
    try {
      await _preferences.setDouble(_levelKey, level);
      await _preferences.setBool(_mutedKey, muted);
    } on Object {
      // A TV without storage keeps the volume until the page reloads.
    }
  }
}

/// The volume every audio, video and YouTube player below [MediaVolumeScope]
/// plays with. New media start with it, running media follow at once.
class MediaVolume extends ChangeNotifier {
  /// Creates the volume, read from [store] by [load].
  MediaVolume({MediaVolumeStore? store}) : _store = store;

  final MediaVolumeStore? _store;
  double _level = 1;
  bool _muted = false;

  /// Level from 0 to 1, also while [muted].
  double get level => _level;

  /// Whether the sound is off.
  bool get muted => _muted;

  /// What the players use: 0 while muted.
  double get effective => _muted ? 0 : _level;

  /// Restores the stored volume.
  Future<void> load() async {
    final stored = await _store?.read();
    if (stored == null) return;
    _level = stored.level;
    _muted = stored.muted;
    notifyListeners();
  }

  /// Sets the level; a level above 0 also ends the mute.
  void setLevel(double level) {
    _level = level.clamp(0.0, 1.0);
    if (_level > 0) _muted = false;
    _changed();
  }

  /// Switches the sound off or on again.
  void toggleMute() {
    _muted = !_muted;
    // Unmuting at 0 would stay silent.
    if (!_muted && _level == 0) _level = 0.5;
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_store?.write(_level, _muted));
  }
}

/// Provides a [MediaVolume] to the media below (the TV page).
class MediaVolumeScope extends InheritedNotifier<MediaVolume> {
  /// Creates the scope.
  const MediaVolumeScope({
    required MediaVolume volume,
    required super.child,
    super.key,
  }) : super(notifier: volume);

  /// The volume of this device, `null` where the device volume rules.
  static MediaVolume? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaVolumeScope>()?.notifier;
}

/// Mute button and slider for the [MediaVolume] of this device; nothing
/// without a [MediaVolumeScope].
class MediaVolumeControl extends StatelessWidget {
  /// Creates the control.
  const MediaVolumeControl({this.width = 160, super.key});

  /// Width of the slider.
  final double width;

  @override
  Widget build(BuildContext context) {
    final volume = MediaVolumeScope.of(context);
    if (volume == null) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('media-volume'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('media-mute'),
          tooltip: volume.muted
              ? context.tr('Ton einschalten')
              : context.tr('Stummschalten'),
          onPressed: volume.toggleMute,
          icon: Icon(
            volume.effective == 0
                ? Icons.volume_off
                : volume.effective < 0.5
                ? Icons.volume_down
                : Icons.volume_up,
          ),
        ),
        SizedBox(
          width: width,
          child: Slider(
            key: const ValueKey('media-volume-slider'),
            value: volume.effective,
            label: context.tr('Lautstärke {0} %', [
              (volume.effective * 100).round(),
            ]),
            semanticFormatterCallback: (value) =>
                context.tr('Lautstärke {0} %', [(value * 100).round()]),
            onChanged: volume.setLevel,
          ),
        ),
      ],
    );
  }
}
