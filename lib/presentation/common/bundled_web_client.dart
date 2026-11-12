/// Flutter asset backed source for the bundled web player.
///
/// Lives in the presentation layer on purpose: `lib/backend/` must stay free of
/// Flutter imports (Rule 1 in `AGENTS.md`), and `rootBundle` is Flutter. The
/// server only ever sees the platform independent [WebClientBundle] interface.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../backend/web_client_bundle.dart';
import '../../backend/zip_web_client_bundle.dart';

/// Asset key of the packed Flutter Web build.
///
/// Produced by `dart run tool/bundle_web_client.dart`.
const String kWebClientAssetKey = 'assets/web_client/bundle.zip';

/// Returns a bundle that serves the web player packed into the app.
///
/// The asset is optional: a debug run without a prior
/// `dart run tool/bundle_web_client.dart` simply has nothing to serve, and the
/// host reports that in its log instead of refusing to start.
WebClientBundle bundledWebClient({
  AssetBundle? bundle,
  String assetKey = kWebClientAssetKey,
}) {
  final assets = bundle ?? rootBundle;
  return ZipWebClientBundle(
    loadArchive: () async {
      try {
        final data = await assets.load(assetKey);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } on FlutterError {
        // Asset not declared or not present in this build flavour.
        return Uint8List(0);
      }
    },
    description: 'app asset $assetKey',
  );
}

/// Returns this app's `version+build`, the format of the web bundle's
/// `version.json` (see `readWebClientVersion`), or `null` when unknown.
Future<String?> hostAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  if (info.version.isEmpty) return null;
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version}+${info.buildNumber}';
}
