/// Results of reading the host's Wi-Fi from the operating system.
library;

import '../../../core/models/guest_wifi.dart';

/// Outcome of [readSystemWifi].
sealed class SystemWifiRead {
  const SystemWifiRead();
}

/// The connected network including its password.
final class SystemWifiFound extends SystemWifiRead {
  const SystemWifiFound(this.wifi);
  final GuestWifi wifi;
}

/// The network is known, but Windows only hands out the key to an
/// administrator; [readSystemWifi] with `elevated: true` asks for consent.
final class SystemWifiNeedsElevation extends SystemWifiRead {
  const SystemWifiNeedsElevation(this.wifi);

  /// Credentials without password.
  final GuestWifi wifi;
}

/// No Wi-Fi connection, the read was cancelled or the network cannot be
/// shared. [message] is a translation key, [details] optional.
final class SystemWifiUnavailable extends SystemWifiRead {
  const SystemWifiUnavailable(this.message, [this.details]);
  final String message;
  final String? details;
}
