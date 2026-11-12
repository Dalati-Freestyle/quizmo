import '../../core/net/lan_discovery.dart';

LanDiscoveryBackend createLanDiscoveryBackend() => _UnsupportedDiscovery();

final class _UnsupportedDiscovery implements LanDiscoveryBackend {
  @override
  bool get isSupported => false;
  @override
  Stream<void> get networkChanges => const Stream.empty();
  @override
  Future<LanBrowser> browse() => Future.error(_unsupported);
  @override
  Future<LanRegistration> publish({required String name, required int port}) =>
      Future.error(_unsupported);
  static const _unsupported = LanDiscoveryException(
    LanDiscoveryProblem.unsupported,
    'LAN discovery is not supported on this platform.',
  );
}
