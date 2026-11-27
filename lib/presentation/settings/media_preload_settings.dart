/// Player setting: preload the media of a quiz in the lobby.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Whether this device downloads all media in the lobby (default) or only
/// when a question needs them (mobile data, little memory).
class MediaPreloadSettings {
  MediaPreloadSettings();

  /// The setting of this app.
  static MediaPreloadSettings instance = MediaPreloadSettings();

  /// Replaces [instance] (tests).
  @visibleForTesting
  static void useSettings(MediaPreloadSettings settings) => instance = settings;

  static const _key = 'quizmo.player.preload-media';

  late final _preferences = SharedPreferencesAsync();

  /// The current choice; `true` until the stored one is read.
  final enabled = ValueNotifier<bool>(true);

  bool _loaded = false;

  /// Reads the stored choice once.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      enabled.value = await _preferences.getBool(_key) ?? true;
    } on Object {
      // Unknown: preloading stays on.
    }
  }

  /// Stores [value] and applies it at once.
  Future<void> save(bool value) async {
    enabled.value = value;
    try {
      await _preferences.setBool(_key, value);
    } on Object {
      // Applies until the app restarts.
    }
  }
}

/// Switch in the settings of a player device.
class MediaPreloadSwitch extends StatefulWidget {
  const MediaPreloadSwitch({super.key});

  @override
  State<MediaPreloadSwitch> createState() => _MediaPreloadSwitchState();
}

class _MediaPreloadSwitchState extends State<MediaPreloadSwitch> {
  final settings = MediaPreloadSettings.instance;

  @override
  void initState() {
    super.initState();
    unawaited(settings.load());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: settings.enabled,
    builder: (context, enabled, _) => SwitchListTile(
      key: const ValueKey('settings-preload-media'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.download_for_offline_outlined),
      title: Text(context.tr('Medien in der Lobby vorladen')),
      subtitle: Text(
        context.tr(
          'Lädt Bilder, Audio und Videos des Quiz vor dem Start verschlüsselt herunter, damit im Quiz nichts mehr nachlädt. Aus: erst bei Bedarf laden (spart mobile Daten und Speicher).',
        ),
      ),
      value: enabled,
      onChanged: (value) => unawaited(settings.save(value)),
    ),
  );
}
