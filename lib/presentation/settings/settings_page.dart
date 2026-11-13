import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import 'app_version_label.dart';
import 'locale_cubit.dart';
import 'example_quiz_settings.dart' deferred as advanced;
import '../quizmaster/layout/dashboard_layout_settings_page.dart'
    deferred as admin_layout;
import '../quizmaster/wifi/guest_wifi_settings_page.dart'
    deferred as guest_wifi;
import 'ai_guide_download.dart' deferred as ai_guide;

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    this.onExamplesChanged,
    this.hostSettings = true,
    super.key,
  });

  final Future<void> Function()? onExamplesChanged;

  /// Whether host-only entries (admin view, guest Wi-Fi) are offered.
  final bool hostSettings;

  @override
  Widget build(BuildContext context) {
    // Isolated widget previews do not own application preferences.
    final controller = context.read<LocaleCubit?>();
    if (controller == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: context.tr('Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BlocProvider.value(
            value: controller,
            child: SettingsPage(
              onExamplesChanged: onExamplesChanged,
              hostSettings: hostSettings,
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    this.onExamplesChanged,
    this.loadVersion,
    this.hostSettings = true,
    super.key,
  });

  final Future<void> Function()? onExamplesChanged;

  /// Whether host-only entries (admin view, guest Wi-Fi) are offered.
  final bool hostSettings;

  /// Overrides how the version is read (tests); defaults to the platform.
  final AppVersionLoader? loadVersion;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Future<void> _advancedLoad = advanced.loadLibrary();

  Future<void> _open(Future<Widget> Function() load) async {
    final page = await load();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _downloadGuide() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('Anleitung gespeichert.');
    final failed = context.tr('Die Anleitung konnte nicht gespeichert werden.');
    final title = context.tr('KI-Anleitung speichern');
    final german = Localizations.localeOf(context).languageCode == 'de';
    try {
      await ai_guide.loadLibrary();
      if (await ai_guide.saveAiQuizGuide(dialogTitle: title, german: german)) {
        messenger.showSnackBar(SnackBar(content: Text(saved)));
      }
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Settings'))),
    body: BlocBuilder<LocaleCubit, LocaleSettingsState>(
      builder: (context, state) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.tr('Language'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Use the system or browser language, or choose a language for this device.',
            ),
          ),
          const SizedBox(height: 20),
          RadioGroup<LanguagePreference>(
            groupValue: state.preference,
            onChanged: (value) {
              if (value != null) context.read<LocaleCubit>().select(value);
            },
            child: Column(
              children: [
                RadioListTile(
                  value: LanguagePreference.system,
                  title: Text(context.tr('System language')),
                ),
                const RadioListTile(
                  value: LanguagePreference.de,
                  title: Text('Deutsch'),
                ),
                const RadioListTile(
                  value: LanguagePreference.en,
                  title: Text('English'),
                ),
              ],
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(
              context.tr(state.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () =>
                  context.read<LocaleCubit>().select(state.preference),
              child: Text(context.tr('Retry')),
            ),
          ],
          if (widget.hostSettings) ...[
            const Divider(height: 48),
            Text(
              context.tr('Spielleitung'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ListTile(
              key: const ValueKey('settings-admin-layout'),
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: Text(context.tr('Admin-Ansicht anpassen')),
              subtitle: Text(
                context.tr('Reihenfolge, Farben und sichtbare Bereiche'),
              ),
              onTap: () => _open(() async {
                await admin_layout.loadLibrary();
                return admin_layout.DashboardLayoutSettingsPage();
              }),
            ),
            if (!kIsWeb)
              ListTile(
                key: const ValueKey('settings-guest-wifi'),
                leading: const Icon(Icons.wifi),
                title: Text(context.tr('Gäste-WLAN')),
                subtitle: Text(
                  context.tr('WLAN-Code, der auf dem TV angezeigt werden kann'),
                ),
                onTap: () => _open(() async {
                  await guest_wifi.loadLibrary();
                  return guest_wifi.GuestWifiSettingsPage();
                }),
              ),
            ListTile(
              key: const ValueKey('settings-ai-guide'),
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(context.tr('Quiz mit KI erstellen')),
              subtitle: Text(
                context.tr(
                  'Anleitung für ChatGPT, Claude & Co. herunterladen. Die KI erstellt damit im Gespräch eine importierbare Quizdatei.',
                ),
              ),
              trailing: const Icon(Icons.download_outlined),
              onTap: _downloadGuide,
            ),
          ],
          const Divider(height: 48),
          Text(
            context.tr('Advanced settings'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          FutureBuilder<void>(
            future: _advancedLoad,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(context.tr('Could not load advanced settings.'));
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return advanced.ExampleQuizSettings(
                onChanged: widget.onExamplesChanged,
              );
            },
          ),
          const Divider(height: 48),
          widget.loadVersion == null
              ? const AppVersionLabel()
              : AppVersionLabel(load: widget.loadVersion!),
        ],
      ),
    ),
  );
}
