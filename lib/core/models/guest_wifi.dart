/// Guest Wi-Fi credentials the host may show on the TV screen.
///
/// Pure Dart: the model, its `WIFI:` QR payload and its validation are shared
/// by the host dashboard, the socket hub and the TV screen.
library;

import 'dart:convert';

import 'json.dart';

/// Security type of a guest network, as understood by the `WIFI:` QR format.
enum WifiSecurity {
  /// WPA/WPA2 personal (also accepted for WPA2/WPA3 transition networks).
  wpa('WPA'),

  /// WPA3-only (SAE).
  sae('SAE'),

  /// Legacy WEP.
  wep('WEP'),

  /// Open network without password.
  open('nopass');

  const WifiSecurity(this.qrTag);

  /// Value of the `T:` field in a `WIFI:` payload.
  final String qrTag;

  /// Maps a `T:` value (case-insensitive) to a security type.
  static WifiSecurity fromQrTag(String? tag) =>
      switch (tag?.trim().toUpperCase()) {
        null || '' || 'NOPASS' => WifiSecurity.open,
        'WEP' => WifiSecurity.wep,
        'SAE' || 'WPA3' => WifiSecurity.sae,
        _ => WifiSecurity.wpa,
      };
}

/// Credentials of the network guests should join.
final class GuestWifi {
  /// Creates guest Wi-Fi credentials.
  const GuestWifi({
    required this.ssid,
    this.password = '',
    this.security = WifiSecurity.wpa,
    this.hidden = false,
  });

  /// Restores credentials from [json] (protocol and local storage).
  factory GuestWifi.fromJson(JsonMap json) {
    final security = json.readString('security');
    final wifi = GuestWifi(
      ssid: json.readString('ssid'),
      password: json.readString('password'),
      security: WifiSecurity.values.firstWhere(
        (value) => value.name == security,
        orElse: () =>
            throw JsonContractException('Unknown Wi-Fi security "$security".'),
      ),
      hidden: json.readBool('hidden'),
    );
    if (wifi.validationError != null) {
      throw JsonContractException(wifi.validationError!);
    }
    return wifi;
  }

  /// Parses a `WIFI:` QR payload, for example from Android's "Share Wi-Fi"
  /// screen. Returns `null` when [payload] is not a Wi-Fi code.
  static GuestWifi? tryParseQr(String payload) {
    final text = payload.trim();
    if (!text.toUpperCase().startsWith('WIFI:')) return null;
    final fields = <String, String>{};
    final body = text.substring(5);
    var key = StringBuffer();
    var value = StringBuffer();
    var inValue = false;
    for (var i = 0; i < body.length; i++) {
      final char = body[i];
      if (char == r'\' && i + 1 < body.length) {
        (inValue ? value : key).write(body[++i]);
      } else if (char == ':' && !inValue) {
        inValue = true;
      } else if (char == ';') {
        if (inValue) {
          fields[key.toString().trim().toUpperCase()] = value.toString();
        }
        key = StringBuffer();
        value = StringBuffer();
        inValue = false;
      } else {
        (inValue ? value : key).write(char);
      }
    }
    if (inValue) fields[key.toString().trim().toUpperCase()] = value.toString();
    final ssid = fields['S'];
    if (ssid == null || ssid.isEmpty) return null;
    final security = WifiSecurity.fromQrTag(fields['T']);
    return GuestWifi(
      ssid: ssid,
      password: security == WifiSecurity.open ? '' : fields['P'] ?? '',
      security: security,
      hidden: fields['H']?.toLowerCase() == 'true',
    );
  }

  /// Network name.
  final String ssid;

  /// Pre-shared key; empty for [WifiSecurity.open].
  final String password;

  /// Security type.
  final WifiSecurity security;

  /// Whether the network does not broadcast its name.
  final bool hidden;

  /// Problem that prevents a scannable code, or `null` when valid.
  ///
  /// The texts are translation keys.
  String? get validationError {
    final ssidBytes = utf8.encode(ssid).length;
    if (ssid.trim().isEmpty || ssidBytes > 32) {
      return 'Enter a Wi-Fi name with 1 to 32 bytes.';
    }
    return switch (security) {
      WifiSecurity.open => null,
      WifiSecurity.wpa || WifiSecurity.sae
          when !(password.length >= 8 && password.length <= 63 ||
              RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(password)) =>
        'A WPA password has 8 to 63 characters.',
      WifiSecurity.wep when ![5, 10, 13, 26].contains(password.length) =>
        'A WEP key has 5, 10, 13 or 26 characters.',
      _ => null,
    };
  }

  /// The `WIFI:` payload understood by the camera apps of iOS and Android.
  String toQrPayload() {
    final buffer = StringBuffer('WIFI:T:${security.qrTag};S:${_escape(ssid)};');
    if (security != WifiSecurity.open) {
      buffer.write('P:${_escape(password)};');
    }
    if (hidden) buffer.write('H:true;');
    buffer.write(';');
    return buffer.toString();
  }

  /// Serializes the credentials.
  JsonMap toJson() => {
    'ssid': ssid,
    'password': password,
    'security': security.name,
    'hidden': hidden,
  };

  /// Returns a copy with the given fields replaced.
  GuestWifi copyWith({
    String? ssid,
    String? password,
    WifiSecurity? security,
    bool? hidden,
  }) => GuestWifi(
    ssid: ssid ?? this.ssid,
    password: password ?? this.password,
    security: security ?? this.security,
    hidden: hidden ?? this.hidden,
  );

  static String _escape(String value) =>
      value.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');

  @override
  bool operator ==(Object other) =>
      other is GuestWifi &&
      other.ssid == ssid &&
      other.password == password &&
      other.security == security &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(ssid, password, security, hidden);

  @override
  String toString() => 'GuestWifi($ssid, ${security.name})';
}
