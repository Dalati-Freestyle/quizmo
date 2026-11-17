/// Advanced setting: upload media files of any size in the quiz editor.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/media_attachment.dart';
import '../l10n/app_localizations.dart';

/// Stores whether the editor accepts media files above [maxMediaBytes].
///
/// The limit only protects devices from accidentally huge quizzes; stored
/// quizzes, imports and player downloads accept any size regardless.
class MediaUploadSettingsStore {
  /// Creates the store.
  MediaUploadSettingsStore();

  /// The store of this app.
  static MediaUploadSettingsStore instance = MediaUploadSettingsStore();

  /// Replaces [instance] (tests).
  @visibleForTesting
  static void useStore(MediaUploadSettingsStore store) => instance = store;

  static const _key = 'quizmo.media.unlimited-uploads';

  late final _preferences = SharedPreferencesAsync();

  /// Whether uploads of any size are allowed; `false` when unknown.
  Future<bool> loadUnlimited() async {
    try {
      return await _preferences.getBool(_key) ?? false;
    } on Object {
      return false;
    }
  }

  /// Stores the choice.
  Future<void> saveUnlimited(bool value) => _preferences.setBool(_key, value);

  /// The upload limit in bytes, or `null` for no limit.
  Future<int?> uploadLimit() async =>
      await loadUnlimited() ? null : maxMediaBytes;
}

/// Switch in the advanced settings that lifts the 20 MiB upload limit.
class MediaUploadSettings extends StatefulWidget {
  /// Creates the switch.
  const MediaUploadSettings({super.key});

  @override
  State<MediaUploadSettings> createState() => _MediaUploadSettingsState();
}

class _MediaUploadSettingsState extends State<MediaUploadSettings> {
  bool? _unlimited;
  String? _error;

  @override
  void initState() {
    super.initState();
    MediaUploadSettingsStore.instance.loadUnlimited().then((value) {
      if (mounted) setState(() => _unlimited = value);
    });
  }

  Future<void> _change(bool value) async {
    final previous = _unlimited;
    setState(() {
      _unlimited = value;
      _error = null;
    });
    try {
      await MediaUploadSettingsStore.instance.saveUnlimited(value);
    } on Object {
      if (!mounted) return;
      setState(() {
        _unlimited = previous;
        _error = 'The setting could not be saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SwitchListTile(
        key: const ValueKey('settings-unlimited-media'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('Allow media files of any size')),
        subtitle: Text(
          context.tr(
            'Lifts the 20 MiB limit per file when adding media to a quiz. Large files make quizzes, exports and downloads on player devices slow and need a lot of memory.',
          ),
        ),
        value: _unlimited ?? false,
        onChanged: _unlimited == null ? null : _change,
      ),
      if (_error != null)
        Text(
          context.tr(_error!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
