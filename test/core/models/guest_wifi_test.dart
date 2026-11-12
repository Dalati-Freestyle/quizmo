import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/models/models.dart';

void main() {
  group('GuestWifi', () {
    test(
      'builds the standard WIFI: payload and escapes special characters',
      () {
        const wifi = GuestWifi(ssid: r'Café;Net', password: r'p:a,s"s\word');
        expect(
          wifi.toQrPayload(),
          r'WIFI:T:WPA;S:Café\;Net;P:p\:a\,s\"s\\word;;',
        );
        expect(GuestWifi.tryParseQr(wifi.toQrPayload()), wifi);
      },
    );

    test('open and hidden networks', () {
      const open = GuestWifi(ssid: 'Guests', security: WifiSecurity.open);
      expect(open.toQrPayload(), 'WIFI:T:nopass;S:Guests;;');
      const hidden = GuestWifi(ssid: 'H', password: '12345678', hidden: true);
      expect(hidden.toQrPayload(), 'WIFI:T:WPA;S:H;P:12345678;H:true;;');
      expect(GuestWifi.tryParseQr(hidden.toQrPayload()), hidden);
    });

    test('reads the field order Android uses when sharing a network', () {
      expect(
        GuestWifi.tryParseQr(
          r'WIFI:S:Home\;5G;T:SAE;P:correct horse;H:false;;',
        ),
        const GuestWifi(
          ssid: 'Home;5G',
          password: 'correct horse',
          security: WifiSecurity.sae,
        ),
      );
      expect(GuestWifi.tryParseQr('https://example.com'), isNull);
      expect(GuestWifi.tryParseQr('WIFI:T:WPA;P:secret;;'), isNull);
    });

    test('validates names and keys', () {
      expect(const GuestWifi(ssid: '').validationError, isNotNull);
      expect(
        GuestWifi(ssid: 'x' * 33, password: '12345678').validationError,
        isNotNull,
      );
      expect(
        const GuestWifi(ssid: 'Net', password: '1234567').validationError,
        isNotNull,
      );
      expect(
        const GuestWifi(ssid: 'Net', password: '12345678').validationError,
        isNull,
      );
      expect(
        const GuestWifi(
          ssid: 'Net',
          password: '12345',
          security: WifiSecurity.wep,
        ).validationError,
        isNull,
      );
      expect(
        const GuestWifi(
          ssid: 'Net',
          security: WifiSecurity.open,
        ).validationError,
        isNull,
      );
    });

    test('JSON round trip rejects unknown security types', () {
      const wifi = GuestWifi(
        ssid: 'Net',
        password: '12345678',
        security: WifiSecurity.sae,
        hidden: true,
      );
      expect(GuestWifi.fromJson(wifi.toJson()), wifi);
      expect(
        () => GuestWifi.fromJson({...wifi.toJson(), 'security': 'enterprise'}),
        throwsA(isA<JsonContractException>()),
      );
    });
  });
}
