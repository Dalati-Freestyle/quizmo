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
  static const _limitKey = 'quizmo.player.preload-max-mb';

  /// Choices for the limit in MB; `null` means no limit.
  static const limits = <int?>[null, 100, 250, 500, 1000];

  late final _preferences = SharedPreferencesAsync();

  /// The current choice; `true` until the stored one is read.
  final enabled = ValueNotifier<bool>(true);

  /// Quizzes larger than this many MB are not preloaded; `null`: no limit.
  final maxMegabytes = ValueNotifier<int?>(null);

  /// [maxMegabytes] in bytes.
  int? get maxBytes => switch (maxMegabytes.value) {
    final mb? => mb * 1000 * 1000,
    null => null,
  };

  bool _loaded = false;

  /// Reads the stored choice once.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      enabled.value = await _preferences.getBool(_key) ?? true;
      final limit = await _preferences.getInt(_limitKey);
      maxMegabytes.value = limits.contains(limit) ? limit : null;
    } on Object {
      // Unknown: preloading stays on.
    }
  }

  /// Stores the limit [megabytes] (`null`: none) and applies it at once.
  Future<void> saveLimit(int? megabytes) async {
    maxMegabytes.value = megabytes;
    try {
      if (megabytes == null) {
        await _preferences.remove(_limitKey);
      } else {
        await _preferences.setInt(_limitKey, megabytes);
      }
    } on Object {
      // Applies until the app restarts.
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
    builder: (context, enabled, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switch(context, enabled),
        if (enabled)
          ValueListenableBuilder<int?>(
            valueListenable: settings.maxMegabytes,
            builder: (context, limit, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.data_usage),
              title: Text(context.tr('Höchstens vorladen')),
              subtitle: Text(
                context.tr(
                  'Größere Quizze werden nicht vorgeladen; ihre Medien laden erst im Quiz.',
                ),
              ),
              trailing: DropdownButton<int?>(
                key: const ValueKey('settings-preload-limit'),
                value: limit,
                items: [
                  for (final choice in MediaPreloadSettings.limits)
                    DropdownMenuItem(
                      value: choice,
                      child: Text(
                        choice == null
                            ? context.tr('Unbegrenzt')
                            : choice >= 1000
                            ? '${choice ~/ 1000} GB'
                            : '$choice MB',
                      ),
                    ),
                ],
                onChanged: (value) => unawaited(settings.saveLimit(value)),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _switch(BuildContext context, bool enabled) => SwitchListTile(
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
  );
}
