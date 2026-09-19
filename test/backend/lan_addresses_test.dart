/// Unit tests of the LAN address ranking.
///
/// The motivating case is a Pixel on Wi-Fi *and* mobile data: it reports both
/// `192.168.2.188` (`wlan0`) and `192.0.0.4` (`v4-rmnet16`, the RFC 7335
/// 464XLAT translation address). Announcing the latter as the join URL makes
/// every guest run into `ERR_CONNECTION_TIMED_OUT`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/backend/lan_addresses.dart';
import 'package:quizmo/backend/server_contract.dart';

void main() {
  group('sortLanAddresses', () {
    test('prefers the Wi-Fi address over the mobile CLAT address', () {
      // Deliberately listed worst-first, the order `NetworkInterface.list()`
      // is free to return.
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: '192.0.0.4', interfaceName: 'v4-rmnet16'),
        LanAddressCandidate(address: '192.168.2.188', interfaceName: 'wlan0'),
      ]);

      expect(sorted.first, '192.168.2.188');
      expect(sorted, contains('192.0.0.4'));
      expect(sorted.last, kLoopbackAddress);
    });

    test('prefers a private address on a Wi-Fi interface over a tunnel', () {
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: '10.8.0.2', interfaceName: 'tun0'),
        LanAddressCandidate(address: '192.168.1.42', interfaceName: 'wlan0'),
      ]);

      expect(sorted.first, '192.168.1.42');
    });

    test('ranks carrier grade NAT and link-local below private space', () {
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: '169.254.7.7', interfaceName: 'eth0'),
        LanAddressCandidate(address: '100.64.0.9', interfaceName: 'rmnet0'),
        LanAddressCandidate(address: '172.20.3.4', interfaceName: 'eth0'),
      ]);

      expect(sorted.take(3), ['172.20.3.4', '100.64.0.9', '169.254.7.7']);
    });

    test('always offers loopback, even without any interface', () {
      expect(sortLanAddresses(const []), [kLoopbackAddress]);
    });

    test('does not duplicate loopback when it was enumerated', () {
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: kLoopbackAddress, interfaceName: 'lo'),
        LanAddressCandidate(address: '192.168.1.5', interfaceName: 'wlan0'),
      ]);

      expect(sorted, ['192.168.1.5', kLoopbackAddress]);
      expect(sorted.where((a) => a == kLoopbackAddress), hasLength(1));
    });

    test('removes duplicate addresses reported by several interfaces', () {
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: '192.168.1.5', interfaceName: 'wlan0'),
        LanAddressCandidate(address: '192.168.1.5', interfaceName: 'br0'),
      ]);

      expect(sorted, ['192.168.1.5', kLoopbackAddress]);
    });

    test('keeps discovery order for equally ranked addresses', () {
      final sorted = sortLanAddresses(const [
        LanAddressCandidate(address: '192.168.1.9', interfaceName: 'wlan0'),
        LanAddressCandidate(address: '192.168.1.8', interfaceName: 'eth0'),
      ]);

      expect(sorted.take(2), ['192.168.1.9', '192.168.1.8']);
    });
  });

  group('lanAddressRank', () {
    test('rates a private Wi-Fi address best', () {
      expect(
        lanAddressRank('192.168.2.188', interfaceName: 'wlan0'),
        lessThan(lanAddressRank('192.0.0.4', interfaceName: 'v4-rmnet16')),
      );
    });

    test('rates loopback worse than any routable address', () {
      expect(
        lanAddressRank('8.8.8.8', interfaceName: 'eth0'),
        lessThan(lanAddressRank(kLoopbackAddress, interfaceName: 'lo')),
      );
    });

    test('rejects malformed input instead of throwing', () {
      expect(lanAddressRank('not-an-ip'), 90);
      expect(lanAddressRank('192.168.1'), 90);
      expect(lanAddressRank('192.168.1.999'), 90);
    });
  });

  group('isPrivateIpv4', () {
    test('covers the RFC 1918 boundaries', () {
      expect(isPrivateIpv4(parseIpv4('172.15.0.1')!), isFalse);
      expect(isPrivateIpv4(parseIpv4('172.16.0.1')!), isTrue);
      expect(isPrivateIpv4(parseIpv4('172.31.255.254')!), isTrue);
      expect(isPrivateIpv4(parseIpv4('172.32.0.1')!), isFalse);
      expect(isPrivateIpv4(parseIpv4('10.0.0.1')!), isTrue);
      expect(isPrivateIpv4(parseIpv4('192.168.0.1')!), isTrue);
      expect(isPrivateIpv4(parseIpv4('192.169.0.1')!), isFalse);
    });
  });

  group('ServerEndpoint', () {
    test('announces the best ranked address as the join URL', () {
      const endpoint = ServerEndpoint(
        port: 8080,
        addresses: ['192.168.2.188', '192.0.0.4', kLoopbackAddress],
      );

      expect(endpoint.lanUri.toString(), 'http://192.168.2.188:8080');
      expect(endpoint.loopbackUri.toString(), 'http://127.0.0.1:8080');
    });

    test('exposes every alternative a guest could try', () {
      const endpoint = ServerEndpoint(
        port: 8080,
        addresses: ['192.168.2.188', '192.0.0.4', kLoopbackAddress],
      );

      expect(endpoint.joinableAddresses, ['192.168.2.188', '192.0.0.4']);
    });

    test('falls back to loopback when nothing else was found', () {
      const endpoint = ServerEndpoint(
        port: 8080,
        addresses: [kLoopbackAddress],
      );

      expect(endpoint.lanAddress, kLoopbackAddress);
      expect(endpoint.joinableAddresses, isEmpty);
    });
  });
}

