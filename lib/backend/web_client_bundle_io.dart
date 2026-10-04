/// `dart:io` sources for the bundled web player.
///
/// Used by headless/Docker deployments and during development, where the
/// Flutter Web build simply sits on disk and does not need to be packed into
/// the app bundle. This library is `dart:io` only and must therefore never be
/// imported from anything reachable by a Flutter Web build (see Rule 4 in
/// `AGENTS.md`); `embedded_server.dart` is the only intended consumer.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'web_client_bundle.dart';
import 'zip_web_client_bundle.dart';

/// Serves the Flutter Web build straight out of a directory such as
/// `build/web`.
final class DirectoryWebClientBundle implements WebClientBundle {
  /// Creates a bundle rooted at [root].
  DirectoryWebClientBundle(this.root);

  /// Directory that holds `index.html`.
  final Directory root;

  @override
  String get description => 'directory ${root.path}';

  @override
  Future<int> prepare() async {
    if (!root.existsSync()) return 0;
    return root.list(recursive: true).where((e) => e is File).length;
  }

  @override
  Future<Uint8List?> read(String path) async {
    // `path` arrives normalised from the handler, but a defensive check keeps
    // a crafted request from reaching outside the root.
    final absoluteRoot = p.normalize(root.absolute.path);
    final target = p.normalize(
      p.join(absoluteRoot, p.joinAll(path.split('/'))),
    );
    if (!p.isWithin(absoluteRoot, target)) return null;

    final file = File(target);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }
}

/// Returns a bundle for the zip archive at [path], or `null` if it is missing.
WebClientBundle? zipWebClientBundleFromFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return ZipWebClientBundle(
    loadArchive: file.readAsBytes,
    description: 'zip $path',
  );
}
