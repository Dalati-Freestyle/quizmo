/// Platform aware factory for the embedded host.
///
/// Importing `embedded_server.dart` directly would drag `dart:io` into a
/// Flutter Web build and break compilation for the very clients that are
/// supposed to *join* a quiz. This conditional export keeps the presentation
/// layer platform agnostic.
library;

export 'server_launcher_stub.dart'
    if (dart.library.io) 'server_launcher_io.dart';

