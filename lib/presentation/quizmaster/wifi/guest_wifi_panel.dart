/// Host dashboard panel: guest Wi-Fi shown as a second QR code on the TV.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/engine/guest_wifi_cubit.dart';
import '../../../core/models/guest_wifi.dart';
import '../../common/adaptive_layout.dart';
import '../../l10n/app_localizations.dart';
import 'guest_wifi_store.dart';
import 'system_wifi.dart';
import 'wifi_qr_image.dart';

/// Lets the quizmaster pick the guest network and show it on the TV.
class GuestWifiPanel extends StatefulWidget {
  const GuestWifiPanel({
    this.guestWifi,
    this.editorOnly = false,
    this.store,
    this.currentNetwork = currentWifiName,
    super.key,
  });

  /// Announcement forwarded to TV screens on this LAN; `null` in the
  /// settings, where nothing is published.
  final GuestWifiCubit? guestWifi;

  /// Only edits the stored networks (settings screen): no TV switch, and the
  /// stored "show on TV" choice of the dashboard stays unchanged.
  final bool editorOnly;

  /// Secure storage; replaced in tests.
  final GuestWifiStore? store;

  /// Name of the network this device is connected to, if known.
  final Future<String?> Function() currentNetwork;

  @override
  State<GuestWifiPanel> createState() => _GuestWifiPanelState();
}

class _GuestWifiPanelState extends State<GuestWifiPanel> {
  late final GuestWifiStore _store = widget.store ?? GuestWifiStore();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  WifiSecurity _security = WifiSecurity.wpa;
  bool _hidden = false;
  bool _showPassword = false;
  bool _busy = true;
  String? _message;
  GuestWifiSettings _settings = const GuestWifiSettings();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  GuestWifi get _draft => GuestWifi(
    ssid: _ssid.text.trim(),
    password: _security == WifiSecurity.open ? '' : _password.text,
    security: _security,
    hidden: _hidden,
  );

  bool get _isSaved => _settings.networks.contains(_draft);

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
    final preferred = settings.preferred(current);
    setState(() {
      _settings = settings;
      _busy = false;
      if (preferred != null) {
        _fill(preferred);
      } else if (current != null) {
        _ssid.text = current;
      }
    });
    if (settings.showOnTv && preferred != null) {
      widget.guestWifi?.publish(preferred);
    }
  }

  void _fill(GuestWifi wifi) {
    _ssid.text = wifi.ssid;
    _password.text = wifi.password;
    _security = wifi.security;
    _hidden = wifi.hidden;
  }

  Future<void> _save({required bool showOnTv}) async {
    final wifi = _draft;
    if (wifi.validationError != null) {
      setState(() => _message = wifi.validationError);
      return;
    }
    if (widget.editorOnly) showOnTv = _settings.showOnTv;
    final settings = _settings.remember(wifi, showOnTv: showOnTv);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _store.save(settings);
      _settings = settings;
      _message = 'Saved encrypted on this device.';
    } on Object {
      _message = 'Could not save the Wi-Fi details on this device.';
    }
    if (!widget.editorOnly) widget.guestWifi?.publish(showOnTv ? wifi : null);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(bool show) async {
    if (!show) {
      widget.guestWifi?.publish(null);
      final settings = GuestWifiSettings(
        networks: _settings.networks,
        lastSsid: _settings.lastSsid,
      );
      setState(() => _settings = settings);
      try {
        await _store.save(settings);
      } on Object {
        // Hiding works anyway; the preference is retried with the next save.
      }
      return;
    }
    await _save(showOnTv: true);
  }

  Future<void> _forget() async {
    final settings = _settings.forget(_draft.ssid);
    widget.guestWifi?.publish(null);
    setState(() {
      _settings = settings;
      _password.clear();
      _message = 'Wi-Fi details removed from this device.';
    });
    try {
      await _store.save(settings);
    } on Object {
      setState(
        () => _message = 'Could not save the Wi-Fi details on this device.',
      );
    }
  }

  Future<void> _readFromSystem() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    var result = await readSystemWifi();
    if (result is SystemWifiNeedsElevation && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Administrator approval needed')),
          content: Text(
            context.tr(
              'Windows only reveals the Wi-Fi password after you confirm it. Windows will ask for permission next (Windows Hello or administrator password).',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('Continue')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        result = await readSystemWifi(elevated: true);
        if (result is SystemWifiNeedsElevation) {
          result = const SystemWifiUnavailable(
            'Windows did not release the password.',
          );
        }
      }
    }
    if (!mounted) return;
    switch (result) {
      case SystemWifiFound(:final wifi):
        setState(() => _fill(wifi));
        await _save(showOnTv: true);
        return;
      case SystemWifiNeedsElevation(:final wifi):
        setState(() {
          _fill(wifi.copyWith(password: _password.text));
          _message = 'Enter the password manually.';
        });
      case SystemWifiUnavailable(:final message, :final details):
        setState(
          () => _message = details == null
              ? message
              : '${context.tr(message)} ($details)',
        );
    }
    setState(() => _busy = false);
  }

  Future<void> _importQrImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    GuestWifi? wifi;
    try {
      final bytes = await file.readAsBytes();
      wifi = await decodeWifiQrImage(bytes);
    } on Object {
      wifi = null;
    }
    if (!mounted) return;
    if (wifi == null) {
      setState(() {
        _busy = false;
        _message = 'No Wi-Fi QR code found in this picture.';
      });
      return;
    }
    setState(() => _fill(wifi!));
    await _save(showOnTv: true);
  }

  @override
  Widget build(BuildContext context) {
    final error = _draft.validationError;
    final shown = _settings.showOnTv && widget.guestWifi?.state != null;
    return PanelCard(
      title: context.tr('Guest Wi-Fi on the TV'),
      icon: Icons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
              'Shows a second QR code on the TV that connects guests to this Wi-Fi. The password is stored encrypted on this device and only sent to TV screens on this network.',
            ),
          ),
          if (!widget.editorOnly)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Show Wi-Fi QR code on the TV')),
              value: shown,
              onChanged: _busy || (error != null && !shown) ? null : _toggle,
            ),
          if (_settings.networks.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _isSaved ? _draft.ssid : null,
              decoration: InputDecoration(
                labelText: context.tr('Saved networks'),
              ),
              items: [
                for (final network in _settings.networks)
                  DropdownMenuItem(
                    value: network.ssid,
                    child: Text(network.ssid),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (ssid) {
                      final network = _settings.networks.firstWhere(
                        (network) => network.ssid == ssid,
                      );
                      setState(() => _fill(network));
                      if (shown) unawaited(_save(showOnTv: true));
                    },
            ),
          TextField(
            controller: _ssid,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.tr('Wi-Fi name (SSID)'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_security != WifiSecurity.open)
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.tr('Wi-Fi password'),
                suffixIcon: IconButton(
                  tooltip: context.tr(
                    _showPassword ? 'Hide password' : 'Show password',
                  ),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<WifiSecurity>(
            initialValue: _security,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('Security')),
            items: [
              for (final security in WifiSecurity.values)
                DropdownMenuItem(
                  value: security,
                  child: Text(
                    context.tr(_securityLabel(security)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _security = value!),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.tr('Hidden network')),
            value: _hidden,
            onChanged: _busy
                ? null
                : (value) => setState(() => _hidden = value ?? false),
          ),
          if (_ssid.text.isNotEmpty && error != null)
            Text(
              context.tr(error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr(message)),
            ),
          if (canOpenWifiSettings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr(
                  'Android does not let apps read Wi-Fi passwords. Open the Wi-Fi settings, tap your network and "Share", confirm with your fingerprint or PIN, take a screenshot of the QR code and import it here.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canReadSystemWifi)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _readFromSystem,
                  icon: const Icon(Icons.download),
                  label: Text(context.tr('Use Windows Wi-Fi')),
                ),
              if (canOpenWifiSettings) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => unawaited(openWifiSettings()),
                  icon: const Icon(Icons.settings),
                  label: Text(context.tr('Open Wi-Fi settings')),
                ),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _importQrImage,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(context.tr('Import QR code from picture')),
              ),
              FilledButton(
                onPressed: _busy || error != null
                    ? null
                    : () => _save(showOnTv: shown || !_isSaved),
                child: Text(context.tr('Save')),
              ),
              if (_isSaved)
                TextButton(
                  onPressed: _busy ? null : _forget,
                  child: Text(context.tr('Forget')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _securityLabel(WifiSecurity security) => switch (security) {
    WifiSecurity.wpa => 'WPA/WPA2',
    WifiSecurity.sae => 'WPA3',
    WifiSecurity.wep => 'WEP',
    WifiSecurity.open => 'Open (no password)',
  };
}
