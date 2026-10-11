import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class SavedPlayerSession {
  const SavedPlayerSession({
    required this.host,
    required this.name,
    required this.playerId,
    required this.token,
  });
  final Uri host;
  final String name;
  final String playerId;
  final String token;
}

class PlayerSessionStore {
  static const _key = 'quizmo.player-session.v1';
  late final _preferences = SharedPreferencesAsync();

  Future<SavedPlayerSession?> read() async {
    final value = await _preferences.getString(_key);
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return SavedPlayerSession(
        host: Uri.parse(json['host'] as String),
        name: json['name'] as String,
        playerId: json['playerId'] as String,
        token: json['token'] as String,
      );
    } on Object {
      await clear();
      return null;
    }
  }

  Future<void> save(SavedPlayerSession session) => _preferences.setString(
    _key,
    jsonEncode({
      'host': session.host.origin,
      'name': session.name,
      'playerId': session.playerId,
      'token': session.token,
    }),
  );

  Future<void> clear() => _preferences.remove(_key);
}
