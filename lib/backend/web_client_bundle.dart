/// Platform independent access to the bundled Flutter Web player.
///
/// The embedded host can serve the player client itself, so a guest only needs
/// the LAN address — no app store install, no separate web server. Where those
/// files come from differs per platform (Flutter asset bundle on a phone, a
/// plain directory in Docker), therefore the server only depends on this
/// interface.
///
/// This library is deliberately free of both `dart:io` and Flutter imports so
/// that it can be referenced from the web safe `server_contract.dart` side of
/// the conditional export in `server_launcher.dart`.
library;

import 'dart:typed_data';

/// A source of static files for the `/` route of the embedded host.
abstract interface class WebClientBundle {
  /// Human readable origin of the files, shown in the server log.
  String get description;

  /// Loads the bundle and returns the number of files it contains.
  ///
  /// Implementations must be idempotent: calling this twice does not re-read
  /// the underlying storage. Returning `0` means "nothing to serve", which the
  /// server reports as a warning instead of an error.
  Future<int> prepare();

  /// Returns the bytes of [path], or `null` when the bundle has no such file.
  ///
  /// [path] is always relative and never starts with a slash, for example
  /// `index.html` or `assets/fonts/MaterialIcons-Regular.otf`.
  Future<Uint8List?> read(String path);
}

/// A bundle backed by an in-memory map, used by tests and as an empty default.
final class InMemoryWebClientBundle implements WebClientBundle {
  /// Creates a bundle that serves [files] keyed by relative path.
  const InMemoryWebClientBundle(
    this.files, {
    this.description = 'in-memory bundle',
  });

  /// Creates a bundle that serves nothing.
  const InMemoryWebClientBundle.empty()
    : files = const {},
      description = 'empty bundle';

  /// File contents keyed by relative path.
  final Map<String, Uint8List> files;

  @override
  final String description;

  @override
  Future<int> prepare() async => files.length;

  @override
  Future<Uint8List?> read(String path) async => files[path];
}

