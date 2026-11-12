/// Platform access to the host's own Wi-Fi (conditional export).
///
/// Windows reads the connected network through wlanapi.dll; Android can only
/// open the system Wi-Fi settings, because apps cannot read saved passwords
/// there. The browser build gets a stub.
library;

export 'system_wifi_contract.dart';
export 'system_wifi_stub.dart' if (dart.library.io) 'system_wifi_io.dart';
