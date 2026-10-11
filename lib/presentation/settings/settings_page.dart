import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import 'locale_cubit.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

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
            child: const SettingsPage(),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
        ],
      ),
    ),
  );
}
