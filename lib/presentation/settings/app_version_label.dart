import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';

/// Version and build number of the running app.
typedef AppVersionLoader = Future<({String version, String build})> Function();

Future<({String version, String build})> _platformVersion() async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, build: info.buildNumber);
}

/// Shows "Version 1.2.0 (build 18)" so the host always knows which release
/// they are running. The numbers come from the platform build (exe, APK or
/// the web bundle's `version.json`), i.e. the real artifact, not the sources.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({this.load = _platformVersion, super.key});

  final AppVersionLoader load;

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late final Future<({String version, String build})> _info = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final String text;
      if (snapshot.hasError) {
        text = context.tr('Version unknown');
      } else if (info == null) {
        text = '';
      } else if (info.build.isEmpty) {
        text = context.tr('Version {0}', [info.version]);
      } else {
        text = context.tr('Version {0} (build {1})', [
          info.version,
          info.build,
        ]);
      }
      return SelectableText(
        text,
        key: const ValueKey('app-version'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    },
  );
}
