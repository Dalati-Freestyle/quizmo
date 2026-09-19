/// Entry screen: host a session or join one.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../backend/server_launcher.dart';
import '../player/player_page.dart';
import '../quizmaster/host_dashboard_page.dart';
import 'adaptive_layout.dart';

/// Lets the user pick between the quizmaster and the player experience.
///
/// Hosting is hidden on the web because a browser tab cannot open a listening
/// socket; the stub in `server_launcher_stub.dart` would throw.
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
        title: 'Host a quiz',
        description: embeddedServerSupported
            ? 'Starts the embedded HTTP and web socket server on this device. '
                  'Players join over your local network.'
            : 'Unavailable in the browser: a web page cannot listen on a TCP '
                  'port. Run Quizmo on Android, iOS or desktop to host.',
        actionLabel: 'Open quizmaster dashboard',
        enabled: embeddedServerSupported,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HostDashboardPage()),
        ),
      ),
      _RoleCard(
        icon: Icons.sports_esports,
        title: 'Join as player',
        description:
            'Connect to a host on your network, pick a team and get a buzzer '
            'that is corrected for your network latency.',
        actionLabel: 'Open player view',
        enabled: true,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlayerPage()),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    'Local-first, multi-device quiz platform',
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
                  const SizedBox(height: 24),
                  Text(
                    kIsWeb
                        ? 'Running as a web client — ask the host for their '
                              'LAN address.'
                        : 'Tip: start the host here, then open the Flutter web '
                              'build in two browser tabs to simulate players.',
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

