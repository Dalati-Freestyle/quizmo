/// Entry screen: host a session or join one.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../../backend/server_launcher.dart';
import '../../core/models/models.dart';
import '../player/player_page.dart';
import '../quizmaster/host_dashboard_page.dart' deferred as host_dashboard;
import '../quizmaster/editor/quiz_library_page.dart' deferred as quiz_library;
import 'adaptive_layout.dart';
import 'quizmo_logo.dart';
import '../settings/settings_page.dart';

/// Lets the user pick between the quizmaster and the player experience.
///
/// Native hosts listen on the LAN; browser hosts use the same-origin relay.
class RoleSelectionPage extends StatelessWidget {
  /// Creates the role selection screen.
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = formFactorOf(context).isWide;

    final cards = <Widget>[
      _RoleCard(
        icon: Icons.record_voice_over_outlined,
        title: context.tr("Host a quiz"),
        description: kIsWeb
            ? context.tr(
                "Host an internet game on this website. Quizzes are saved in this browser. Keep the host tab open during play.",
              )
            : embeddedServerSupported
            ? context.tr(
                "Starts the embedded HTTP and web socket server on this device. Players join over your local network.",
              )
            : context.tr("Hosting is unavailable on this platform."),
        actionLabel: context.tr("Open quizmaster dashboard"),
        enabled: embeddedServerSupported,
        onPressed: () => _chooseQuizAndHost(context),
      ),
      _RoleCard(
        icon: Icons.sports_esports,
        title: context.tr("Join as player"),
        description: context.tr(
          "Connect to a host on your network, pick a team and get a buzzer that is corrected for your network latency.",
        ),
        actionLabel: context.tr("Open player view"),
        enabled: true,
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage())),
      ),
    ];

    return Scaffold(
      appBar: AppBar(actions: const [SettingsButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: QuizmoLogo(size: 112)),
                  const SizedBox(height: 16),
                  Text(
                    'Quizmo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr("Local-first, multi-device quiz platform"),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (isWide)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 16),
                          Expanded(child: cards[1]),
                        ],
                      ),
                    )
                  else ...[
                    cards[0],
                    const SizedBox(height: 16),
                    cards[1],
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openQuizLibrary(context),
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text(context.tr("Manage quiz library")),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    kIsWeb
                        ? context.tr(
                            "Create quizzes here or join with the invitation link from your host.",
                          )
                        : context.tr(
                            "Tip: start the host here, then open the Flutter web build in two browser tabs to simulate players.",
                          ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseQuizAndHost(BuildContext context) async {
    final quiz = await _openQuizLibrary(context, selectForHosting: true);
    if (!context.mounted || quiz == null) return;
    await host_dashboard.loadLibrary();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => host_dashboard.HostDashboardPage(quiz: quiz),
      ),
    );
  }

  Future<Quiz?> _openQuizLibrary(
    BuildContext context, {
    bool selectForHosting = false,
  }) async {
    await quiz_library.loadLibrary();
    if (!context.mounted) return null;
    return Navigator.of(context).push<Quiz>(
      MaterialPageRoute<Quiz>(
        builder: (_) =>
            quiz_library.QuizLibraryPage(selectForHosting: selectForHosting),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: enabled ? onPressed : null,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
