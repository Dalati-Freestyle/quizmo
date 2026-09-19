/// Packs the Flutter Web player into the asset the embedded host serves.
///
/// The Flutter Web output is a nested tree (`assets/`, `canvaskit/`, `icons/`,
/// …), but `pubspec.yaml` only bundles files that sit *directly* inside a
/// declared asset folder. Zipping the build into a single asset avoids having
/// to enumerate — and maintain — every nested directory by hand.
///
/// ```console
/// $ dart run tool/bundle_web_client.dart            # build + pack
/// $ dart run tool/bundle_web_client.dart --no-build # pack build/web as-is
/// $ dart run tool/bundle_web_client.dart --debug    # unminified web build
/// ```
///
/// Run this before building the host app (`flutter build apk`, …); the result
/// lands in `assets/web_client/bundle.zip` and is picked up automatically by
/// `bundledWebClient()`.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Files that never need to travel to a browser.
const Set<String> _skippedNames = {'.DS_Store', 'Thumbs.db'};

/// Asset key of the packed player, as declared in `pubspec.yaml`.
const String _assetKey = 'assets/web_client/bundle.zip';

/// Where Flutter copies [_assetKey] inside a web build.
///
/// Without this exclusion the archive would swallow its own previous version on
/// every run — `flutter build web` bundles *all* declared assets, including the
/// player zip, so each pass would roughly double the output size. A browser
/// player never hosts anything, so it has no use for the archive anyway.
const String _selfReference = 'assets/$_assetKey';

Future<int> main(List<String> args) async {
  final shouldBuild = !args.contains('--no-build');
  final isDebug = args.contains('--debug');

  final projectRoot = _findProjectRoot();
  if (projectRoot == null) {
    stderr.writeln('Could not locate pubspec.yaml above this script.');
    return 1;
  }

  final webBuildDir = Directory(p.join(projectRoot, 'build', 'web'));
  final outputFile = File(
    p.join(projectRoot, 'assets', 'web_client', 'bundle.zip'),
  );

  if (shouldBuild) {
    final exitCode = await _runFlutterBuild(
      projectRoot: projectRoot,
      isDebug: isDebug,
    );
    if (exitCode != 0) {
      stderr.writeln('flutter build web failed with exit code $exitCode.');
      return exitCode;
    }
  }

  if (!webBuildDir.existsSync()) {
    stderr.writeln(
      'Missing ${webBuildDir.path}. Run without --no-build, or run '
      '`flutter build web` first.',
    );
    return 1;
  }

  final archive = Archive();
  var fileCount = 0;
  var byteCount = 0;

  final entries =
      webBuildDir.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in entries) {
    final name = p.basename(file.path);
    if (_skippedNames.contains(name)) continue;

    // Zip entries always use forward slashes, independent of the host OS.
    final relative = p.url.joinAll(
      p.split(p.relative(file.path, from: webBuildDir.path)),
    );
    if (relative == _selfReference) continue;

    final bytes = file.readAsBytesSync();
    archive.addFile(ArchiveFile.bytes(relative, bytes));
    fileCount++;
    byteCount += bytes.length;
  }

  if (archive.findFile('index.html') == null) {
    stderr.writeln('No index.html in ${webBuildDir.path} — aborting.');
    return 1;
  }

  final encoded = ZipEncoder().encodeBytes(archive);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsBytesSync(encoded);

  stdout
    ..writeln('Packed $fileCount files (${_mib(byteCount)} raw) into')
    ..writeln('  ${p.relative(outputFile.path, from: projectRoot)} '
        '(${_mib(encoded.length)} compressed)')
    ..writeln('Rebuild the host app to embed the updated player.');
  return 0;
}

Future<int> _runFlutterBuild({
  required String projectRoot,
  required bool isDebug,
}) async {
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  stdout.writeln('Running $executable build web…');
  final process = await Process.start(
    executable,
    ['build', 'web', if (isDebug) '--debug' else '--release'],
    workingDirectory: projectRoot,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  return process.exitCode;
}

/// Walks upwards from this script until a `pubspec.yaml` shows up.
String? _findProjectRoot() {
  var directory = Directory(p.dirname(Platform.script.toFilePath()));
  for (var i = 0; i < 5; i++) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

