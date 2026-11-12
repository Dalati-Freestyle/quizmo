import 'system_wifi_contract.dart';

/// Whether this platform can read the connected Wi-Fi including password.
bool get canReadSystemWifi => false;

/// Whether this platform can open the system Wi-Fi settings.
bool get canOpenWifiSettings => false;

/// Name of the connected Wi-Fi, if the platform reveals it.
Future<String?> currentWifiName() async => null;

/// Reads the connected Wi-Fi.
Future<SystemWifiRead> readSystemWifi({bool elevated = false}) async =>
    const SystemWifiUnavailable('Not supported on this device.');

/// Opens the system Wi-Fi settings.
Future<bool> openWifiSettings() async => false;
