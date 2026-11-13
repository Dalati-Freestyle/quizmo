/// Host dashboard switch that shows the stored guest Wi-Fi on the TV.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/engine/guest_wifi_cubit.dart';
import '../../../core/models/guest_wifi.dart';
import '../../common/adaptive_layout.dart';
import '../../l10n/app_localizations.dart';
import 'guest_wifi_settings_page.dart' deferred as wifi_settings;
import 'guest_wifi_store.dart';
import 'system_wifi.dart';

/// The only guest Wi-Fi control left in the admin view: show it or not.
///
/// The network itself is entered in the settings ("Gäste-WLAN").
class GuestWifiToggle extends StatefulWidget {
  /// Creates the switch.
  const GuestWifiToggle({
    required this.guestWifi,
    this.store,
    this.currentNetwork = currentWifiName,
    super.key,
  });

  /// Announcement forwarded to TV screens on this LAN.
  final GuestWifiCubit guestWifi;

  /// Secure storage; replaced in tests.
  final GuestWifiStore? store;

  /// Name of the network this device is connected to, if known.
  final Future<String?> Function() currentNetwork;

  @override
  State<GuestWifiToggle> createState() => _GuestWifiToggleState();
}

class _GuestWifiToggleState extends State<GuestWifiToggle> {
  late final GuestWifiStore _store = widget.store ?? GuestWifiStore();
  GuestWifiSettings _settings = const GuestWifiSettings();
  GuestWifi? _network;
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    GuestWifiSettings settings;
    String? current;
    try {
      settings = await _store.load();
      current = await widget.currentNetwork();
    } on Object {
      settings = const GuestWifiSettings();
      _message = 'Saved Wi-Fi details could not be read.';
    }
    if (!mounted) return;
    final network = settings.preferred(current);
    setState(() {
      _settings = settings;
      _network = network;
      _busy = false;
    });
    widget.guestWifi.publish(settings.showOnTv ? network : null);
  }

  Future<void> _toggle(bool show) async {
    final network = _network;
    if (show && network == null) return;
    final settings = show
        ? _settings.remember(network!, showOnTv: true)
        : GuestWifiSettings(
            networks: _settings.networks,
            lastSsid: _settings.lastSsid,
          );
    setState(() {
      _settings = settings;
      _message = null;
    });
    widget.guestWifi.publish(show ? network : null);
    try {
      await _store.save(settings);
    } on Object {
      // Showing or hiding works anyway; the choice is saved with the next change.
    }
  }

  Future<void> _openSettings() async {
    await wifi_settings.loadLibrary();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => wifi_settings.GuestWifiSettingsPage(store: _store),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final network = _network;
    final shown = _settings.showOnTv && widget.guestWifi.state != null;
    return PanelCard(
      title: context.tr('Guest Wi-Fi on the TV'),
      icon: Icons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('guest-wifi-toggle'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show Wi-Fi QR code on the TV')),
            subtitle: Text(
              network == null
                  ? context.tr(
                      'Noch kein Gäste-WLAN hinterlegt. Bitte in den Einstellungen eintragen.',
                    )
                  : context.tr('Netzwerk: {0}', [network.ssid]),
            ),
            value: shown,
            onChanged: _busy || network == null ? null : _toggle,
          ),
          if (_message != null) Text(context.tr(_message!)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('guest-wifi-settings'),
              icon: const Icon(Icons.settings_outlined),
              label: Text(
                context.tr('Gäste-WLAN in den Einstellungen bearbeiten'),
              ),
              onPressed: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}
