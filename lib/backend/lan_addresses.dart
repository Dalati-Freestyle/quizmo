/// Ranking of local IPv4 addresses by "can another device on the Wi-Fi reach
/// me here?".
///
/// A phone usually has more than one IPv4 address, and the interesting one is
/// rarely the first that `NetworkInterface.list()` happens to report. A Pixel
/// on mobile data plus Wi-Fi, for example, exposes both `192.168.2.188`
/// (`wlan0`) and `192.0.0.4` (`v4-rmnet…`, the 464XLAT translation address from
/// RFC 7335). Announcing the latter as the join URL produces a connection
/// *timeout* on every guest device, because nothing routes there.
///
/// This library is pure Dart so the choice can be unit tested without opening a
/// single socket.
library;

/// One IPv4 address together with the interface it was discovered on.
final class LanAddressCandidate {
  /// Creates a candidate.
  const LanAddressCandidate({
    required this.address,
    required this.interfaceName,
  });

  /// Dotted quad IPv4 address, for example `192.168.2.188`.
  final String address;

  /// Name of the owning interface, for example `wlan0`.
  final String interfaceName;

  @override
  String toString() => '$address ($interfaceName)';
}

/// Loopback address every host answers on.
const String kLoopbackAddress = '127.0.0.1';

/// Interface name prefixes that carry local network traffic.
///
/// `wlan`/`ap` are Android and Linux Wi-Fi, `eth`/`en` are wired links and the
/// macOS naming scheme, `swlan` shows up on some Android tethering setups.
const List<String> _lanInterfacePrefixes = [
  'wlan',
  'swlan',
  'ap',
  'eth',
  'en',
  'wl',
  'br',
];

/// Rank of [address] as a join URL; lower is better.
///
/// Exposed for tests and for anything that wants to explain the ordering to a
/// user; [sortLanAddresses] is the usual entry point.
int lanAddressRank(String address, {String interfaceName = ''}) {
  final octets = parseIpv4(address);
  if (octets == null) return 90;

  final onLanInterface = isLanInterface(interfaceName);

  return switch (octets) {
    // Loopback: always reachable, never useful to hand to a guest.
    [127, _, _, _] => 80,
    // RFC 7335 IPv4 service continuity prefix — the CLAT address of a
    // 464XLAT mobile connection. Looks private, routes nowhere.
    [192, 0, 0, _] => 70,
    // RFC 3927 link-local; only meaningful without DHCP.
    [169, 254, _, _] => 60,
    // RFC 6598 carrier grade NAT space.
    [100, final b, _, _] when b >= 64 && b <= 127 => 50,
    // RFC 1918 private space: exactly what a living-room quiz runs on.
    _ when isPrivateIpv4(octets) => onLanInterface ? 0 : 10,
    // Anything else is likely public; usable, but rarely what we want.
    _ => onLanInterface ? 20 : 30,
  };
}

/// Whether [name] looks like a local network interface rather than a mobile,
/// tunnel or virtual one.
bool isLanInterface(String name) {
  final lower = name.toLowerCase();
  return _lanInterfacePrefixes.any(lower.startsWith);
}

/// Whether [octets] fall into RFC 1918 private address space.
bool isPrivateIpv4(List<int> octets) => switch (octets) {
  [10, _, _, _] => true,
  [172, final b, _, _] when b >= 16 && b <= 31 => true,
  [192, 168, _, _] => true,
  _ => false,
};

/// Parses a dotted quad into four octets, or returns `null`.
List<int>? parseIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  return octets;
}

/// Returns the addresses of [candidates], best reachable first.
///
/// Loopback is appended last so it is always offered as a fallback — hosting
/// and playing on the same device has to keep working even when the Wi-Fi is
/// off. Duplicates are removed, and equally ranked addresses keep their
/// discovery order so the result is stable across calls.
List<String> sortLanAddresses(Iterable<LanAddressCandidate> candidates) {
  final ranked = <({String address, int rank, int index})>[];
  final seen = <String>{};

  for (final candidate in candidates) {
    if (!seen.add(candidate.address)) continue;
    ranked.add((
      address: candidate.address,
      rank: lanAddressRank(
        candidate.address,
        interfaceName: candidate.interfaceName,
      ),
      index: ranked.length,
    ));
  }

  ranked.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.index.compareTo(b.index);
  });

  final addresses = [for (final entry in ranked) entry.address];
  if (!seen.contains(kLoopbackAddress)) addresses.add(kLoopbackAddress);
  return addresses;
}

