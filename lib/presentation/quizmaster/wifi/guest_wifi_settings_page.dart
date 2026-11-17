/// Settings screen where the guest Wi-Fi for the TV is entered.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'guest_wifi_panel.dart';
import 'guest_wifi_store.dart';

/// Edits the stored guest networks; the admin view only switches the TV code
/// on or off.
class GuestWifiSettingsPage extends StatelessWidget {
  /// Creates the page.
  const GuestWifiSettingsPage({this.store, super.key});

  /// Secure storage; replaced in tests.
  final GuestWifiStore? store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Gäste-WLAN'))),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: GuestWifiPanel(store: store, editorOnly: true),
          ),
        ),
      ),
    ),
  );
}
