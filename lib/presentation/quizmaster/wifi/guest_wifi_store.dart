/// Keeps guest Wi-Fi credentials in the operating system's secure storage
/// (Android Keystore, Windows Credential Manager / DPAPI), one entry per
/// network name.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/models/guest_wifi.dart';
import '../../../core/models/json.dart';

/// Saved guest networks and whether the TV shows one.
final class GuestWifiSettings {
  const GuestWifiSettings({
    this.networks = const [],
    this.lastSsid,
    this.showOnTv = false,
  });

  final List<GuestWifi> networks;
  final String? lastSsid;
  final bool showOnTv;

  /// Network for [currentSsid], else the last used one.
  GuestWifi? preferred(String? currentSsid) {
    for (final ssid in [currentSsid, lastSsid]) {
      for (final network in networks) {
        if (network.ssid == ssid) return network;
      }
    }
    return networks.isEmpty ? null : networks.first;
  }

  /// Stores [wifi] (replacing the entry with the same name) as last used.
  GuestWifiSettings remember(GuestWifi wifi, {required bool showOnTv}) =>
      GuestWifiSettings(
        networks: [
          wifi,
          ...networks.where((network) => network.ssid != wifi.ssid),
        ].take(20).toList(growable: false),
        lastSsid: wifi.ssid,
        showOnTv: showOnTv,
      );

  /// Removes the network called [ssid].
  GuestWifiSettings forget(String ssid) => GuestWifiSettings(
    networks: networks.where((network) => network.ssid != ssid).toList(),
    lastSsid: lastSsid == ssid ? null : lastSsid,
    showOnTv: lastSsid == ssid ? false : showOnTv,
  );

  JsonMap toJson() => {
    'networks': [for (final network in networks) network.toJson()],
    'lastSsid': lastSsid,
    'showOnTv': showOnTv,
  };

  factory GuestWifiSettings.fromJson(JsonMap json) {
    final networks = json['networks'];
    if (networks is! List) {
      throw const JsonContractException('Invalid guest Wi-Fi settings.');
    }
    return GuestWifiSettings(
      networks: [
        for (final network in networks)
          if (network is JsonMap) GuestWifi.fromJson(network),
      ],
      lastSsid: json.readStringOrNull('lastSsid'),
      showOnTv: json.readBool('showOnTv'),
    );
  }
}

/// Reads and writes [GuestWifiSettings].
class GuestWifiStore {
  GuestWifiStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'quizmo.guestWifi.v1';
  final FlutterSecureStorage _storage;

  Future<GuestWifiSettings> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const GuestWifiSettings();
    try {
      return GuestWifiSettings.fromJson(jsonDecode(raw) as JsonMap);
    } on Object {
      return const GuestWifiSettings();
    }
  }

  Future<void> save(GuestWifiSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));
}
