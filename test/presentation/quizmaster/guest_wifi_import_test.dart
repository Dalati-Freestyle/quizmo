import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quizmo/core/models/models.dart';
import 'package:quizmo/presentation/quizmaster/wifi/guest_wifi_store.dart';
import 'package:quizmo/presentation/quizmaster/wifi/wifi_qr_image.dart';
import 'package:quizmo/presentation/quizmaster/wifi/wlan_profile_xml.dart';
import 'package:zxing2/qrcode.dart';

String _profile({
  String auth = 'WPA2PSK',
  String encryption = 'AES',
  String? key = 'quiz-night-123',
  bool protected = false,
}) =>
    '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>Profile &amp; Co</name>
  <SSIDConfig><SSID><hex>4361666520262043C3A9</hex><name>Cafe &amp; C&#233;</name></SSID><nonBroadcast>true</nonBroadcast></SSIDConfig>
  <MSM><security><authEncryption><authentication>$auth</authentication><encryption>$encryption</encryption></authEncryption>
  ${key == null ? '' : '<sharedKey><keyType>passPhrase</keyType><protected>$protected</protected><keyMaterial>$key</keyMaterial></sharedKey>'}
  </security></MSM>
</WLANProfile>''';

void main() {
  group('Windows WLAN profile XML', () {
    test('reads a plain-text WPA2 key and the UTF-8 SSID', () {
      final result = parseWlanProfileXml(_profile());
      expect(
        (result! as WlanProfileCredentials).wifi,
        const GuestWifi(
          ssid: 'Cafe & Cé',
          password: 'quiz-night-123',
          hidden: true,
        ),
      );
    });

    test('reports an encrypted key as needing approval', () {
      final result = parseWlanProfileXml(
        _profile(auth: 'WPA3SAE', key: '01000000D08C9DDF', protected: true),
      );
      expect(result, isA<WlanProfileKeyProtected>());
      expect((result! as WlanProfileKeyProtected).security, WifiSecurity.sae);
    });

    test('open networks need no key, enterprise logins are unsupported', () {
      expect(
        (parseWlanProfileXml(
                  _profile(auth: 'open', encryption: 'none', key: null),
                )!
                as WlanProfileCredentials)
            .wifi
            .security,
        WifiSecurity.open,
      );
      expect(
        parseWlanProfileXml(_profile(auth: 'WPA2', key: null)),
        isA<WlanProfileUnsupported>(),
      );
      expect(parseWlanProfileXml('<html></html>'), isNull);
    });
  });

  test('decodes a Wi-Fi QR code from a screenshot-like picture', () {
    const wifi = GuestWifi(
      ssid: 'Quiz Night',
      password: 'correct horse',
      security: WifiSecurity.sae,
    );
    final matrix = Encoder.encode(
      wifi.toQrPayload(),
      ErrorCorrectionLevel.m,
    ).matrix!;
    const scale = 8;
    final screenshot = img.Image(width: 1080, height: 1600)
      ..clear(img.ColorRgb8(240, 240, 240));
    img.fillRect(
      screenshot,
      x1: 0,
      y1: 0,
      x2: 1080,
      y2: 200,
      color: img.ColorRgb8(30, 60, 120),
    );
    final left = (1080 - matrix.width * scale) ~/ 2;
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            screenshot,
            x1: left + x * scale,
            y1: 500 + y * scale,
            x2: left + (x + 1) * scale - 1,
            y2: 500 + (y + 1) * scale - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    final text = decodeQrText(img.encodePng(screenshot));
    expect(GuestWifi.tryParseQr(text!), wifi);
    expect(
      decodeQrText(img.encodePng(img.Image(width: 50, height: 50))),
      isNull,
    );
  });

  test('settings remember one entry per network and pick the current one', () {
    const a = GuestWifi(ssid: 'A', password: '12345678');
    const b = GuestWifi(ssid: 'B', password: '87654321');
    var settings = const GuestWifiSettings()
        .remember(a, showOnTv: true)
        .remember(b, showOnTv: false)
        .remember(a.copyWith(password: 'changed-pw'), showOnTv: true);
    expect(settings.networks.map((n) => n.ssid), ['A', 'B']);
    expect(settings.preferred('B'), b);
    expect(settings.preferred(null)!.password, 'changed-pw');
    settings = GuestWifiSettings.fromJson(settings.toJson());
    expect(settings.showOnTv, isTrue);
    settings = settings.forget('A');
    expect(settings.preferred(null), b);
    expect(settings.showOnTv, isFalse);
  });
}
