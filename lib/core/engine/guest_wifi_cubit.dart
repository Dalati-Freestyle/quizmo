/// Host-owned guest Wi-Fi announcement for the TV screen.
library;

import 'package:bloc/bloc.dart';

import '../models/guest_wifi.dart';

/// Holds the Wi-Fi credentials the host currently shows on TV screens.
///
/// `null` means no Wi-Fi code is shown. Only the embedded LAN host forwards
/// this to spectators; the internet relay never receives it, and players never
/// see it in their snapshots.
final class GuestWifiCubit extends Cubit<GuestWifi?> {
  /// Creates the cubit, optionally already announcing [initial].
  GuestWifiCubit([super.initial]);

  /// Shows [wifi] on every TV, or hides the code when `null` or invalid.
  void publish(GuestWifi? wifi) =>
      emit(wifi?.validationError == null ? wifi : null);
}
