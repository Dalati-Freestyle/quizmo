/// A [WebClientBundle] backed by a zip archive.
///
/// The Flutter Web build is a deep tree (`assets/`, `canvaskit/`, `icons/`,
/// …). Flutter's `pubspec.yaml` only bundles files that sit *directly* in a
/// declared asset folder, so shipping that tree verbatim would mean listing
/// every nested directory by hand and re-listing it after every upgrade.
/// Packing the build into a single zip sidesteps that entirely.
///
/// The archive is decoded once and then kept in memory. Decoding a zip only
/// reads the central directory; the (compressed) payload of an entry is
/// inflated lazily on the first request and cached afterwards, so a client that
/// never asks for `canvaskit.wasm` never pays for it.
///
/// This library is pure Dart — it works on every platform, which keeps the
/// `dart:io` and Flutter specific parts down to "where do the bytes come from".
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'web_client_bundle.dart';

/// Supplies the raw bytes of the zip archive.
typedef ArchiveLoader = Future<Uint8List> Function();

/// Serves the Flutter Web build from a zip archive.
final class ZipWebClientBundle implements WebClientBundle {
  /// Creates a bundle that decodes the archive returned by [loadArchive].
  ZipWebClientBundle({
    required ArchiveLoader loadArchive,
    this.description = 'zip archive',
  }) : _loadArchive = loadArchive;

  /// Creates a bundle over an already loaded [bytes] archive.
  ZipWebClientBundle.fromBytes(
    Uint8List bytes, {
    this.description = 'zip archive',
  }) : _loadArchive = (() async => bytes);

  @override
  final String description;

  final ArchiveLoader _loadArchive;
  final Map<String, Uint8List> _cache = {};

  Archive? _archive;
  Future<int>? _preparing;

  @override
  Future<int> prepare() => _preparing ??= _decode();

  @override
  Future<Uint8List?> read(String path) async {
    if (path.isEmpty) return null;
    final cached = _cache[path];
    if (cached != null) return cached;

    await prepare();
    final entry = _archive?.findFile(path);
    if (entry == null || !entry.isFile) return null;

    final bytes = entry.readBytes();
    if (bytes == null) return null;
    return _cache[path] = bytes;
  }

  Future<int> _decode() async {
    final bytes = await _loadArchive();
    if (bytes.isEmpty) return 0;
    final archive = ZipDecoder().decodeBytes(bytes);
    _archive = archive;
    return archive.files.where((file) => file.isFile).length;
  }
}
