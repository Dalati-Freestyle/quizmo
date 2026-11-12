import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../../../core/models/guest_wifi.dart';
import 'system_wifi_contract.dart';
import 'windows_wlan.dart';
import 'wlan_profile_xml.dart';

const _channel = MethodChannel('quizmo/system');

/// Whether this platform can read the connected Wi-Fi including password.
bool get canReadSystemWifi => Platform.isWindows;

/// Whether this platform can open the system Wi-Fi settings.
bool get canOpenWifiSettings => Platform.isAndroid;

/// Name of the connected Wi-Fi, if the platform reveals it.
Future<String?> currentWifiName() async {
  if (!Platform.isWindows) return null;
  try {
    final profile = await Isolate.run(readConnectedWlanProfile);
    if (profile?.xml case final xml?) {
      return switch (parseWlanProfileXml(xml)) {
        WlanProfileCredentials(:final wifi) => wifi.ssid,
        WlanProfileKeyProtected(:final ssid) => ssid,
        WlanProfileUnsupported(:final ssid) => ssid,
        null => profile!.profile,
      };
    }
    return profile?.profile;
  } on Object {
    return null;
  }
}

/// Reads the connected Wi-Fi.
///
/// With [elevated] Windows shows its consent prompt (UAC, optionally confirmed
/// with Windows Hello) and exports the profile with `netsh` into a private
/// temporary folder that is deleted right afterwards.
Future<SystemWifiRead> readSystemWifi({bool elevated = false}) async {
  if (!Platform.isWindows) {
    return const SystemWifiUnavailable('Not supported on this device.');
  }
  final ConnectedWlanProfile? profile;
  try {
    profile = await Isolate.run(readConnectedWlanProfile);
  } on Object catch (error) {
    return SystemWifiUnavailable(
      'Windows did not provide the Wi-Fi details.',
      '$error',
    );
  }
  if (profile == null) {
    return const SystemWifiUnavailable(
      'This computer is not connected to a Wi-Fi network.',
    );
  }
  final direct = profile.xml == null ? null : parseWlanProfileXml(profile.xml!);
  if (!elevated || direct is! WlanProfileKeyProtected) {
    return _toRead(direct, profile.profile);
  }
  return _toRead(await _exportElevated(profile.profile), profile.profile);
}

SystemWifiRead _toRead(WlanProfileResult? result, String profile) =>
    switch (result) {
      WlanProfileCredentials(:final wifi) => SystemWifiFound(wifi),
      WlanProfileKeyProtected(:final ssid, :final security, :final hidden) =>
        SystemWifiNeedsElevation(
          GuestWifi(ssid: ssid, security: security, hidden: hidden),
        ),
      WlanProfileUnsupported(:final authentication) => SystemWifiUnavailable(
        'This network uses a sign-in that cannot be shared as a QR code.',
        authentication,
      ),
      null => SystemWifiUnavailable(
        'Windows did not provide the Wi-Fi details.',
        profile,
      ),
    };

Future<WlanProfileResult?> _exportElevated(String profile) async {
  // The profile name ends up inside a quoted netsh argument.
  if (profile.contains('"')) return null;
  final folder = await Directory.systemTemp.createTemp('quizmo-wlan-');
  try {
    final arguments =
        'wlan export profile name="$profile" key=clear folder="${folder.path}"';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Start-Process -FilePath netsh.exe -Verb RunAs -Wait -WindowStyle Hidden "
          "-ArgumentList '${arguments.replaceAll("'", "''")}'",
    ]);
    if (result.exitCode != 0) return null;
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.xml')) {
        continue;
      }
      final parsed = parseWlanProfileXml(await entry.readAsString());
      if (parsed != null) return parsed;
    }
    return null;
  } finally {
    await folder.delete(recursive: true);
  }
}

/// Opens the system Wi-Fi settings.
Future<bool> openWifiSettings() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('openWifiSettings') ?? false;
  } on PlatformException {
    return false;
  }
}
