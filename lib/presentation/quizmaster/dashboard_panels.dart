/// Panels of the quizmaster dashboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/server_contract.dart';
import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/models/models.dart';
import '../../core/sync/clock.dart';
import '../common/adaptive_layout.dart';
import 'host_server_cubit.dart';

/// Start/stop control and reachability information of the embedded server.
class ServerControlPanel extends StatelessWidget {
  /// Creates the server panel.
  const ServerControlPanel({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.connectedPlayers,
    this.onOpenTvPreview,
    super.key,
  });

  /// Current server lifecycle state.
  final HostServerState state;

  /// Starts the server on the configured port.
  final VoidCallback onStart;

  /// Stops the server.
  final VoidCallback onStop;

  /// Number of joined players, rendered next to the endpoint.
  final int connectedPlayers;

  /// Opens the spectator (TV) screen in a full-screen preview on this device.
  ///
  /// Handy to cast the host screen itself, for example with a cable or
  /// "Cast screen"; the preview is the same view a TV browser would show.
  final VoidCallback? onOpenTvPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final endpoint = state.endpoint;

    return PanelCard(
      title: 'Embedded server',
      icon: Icons.dns_outlined,
      trailing: _StatusDot(status: state.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!state.isSupported)
            const EmptyHint(
              'Hosting needs a dart:io platform. Run this build on Android, '
              'iOS, macOS, Windows or Linux.',
              icon: Icons.block,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.status == HostServerStatus.running
                        ? onStop
                        : onStart,
                    icon: Icon(
                      state.status == HostServerStatus.running
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      switch (state.status) {
                        HostServerStatus.running => 'Stop server',
                        HostServerStatus.starting => 'Starting…',
                        HostServerStatus.failed => 'Retry',
                        HostServerStatus.stopped => 'Start server',
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (endpoint != null) ...[
              _CopyableUri(label: 'LAN', uri: endpoint.lanUri),
              _CopyableUri(label: 'This device', uri: endpoint.loopbackUri),
              _CopyableUri(label: 'TV screen', uri: endpoint.lanTvUri),
              InfoRow(label: 'Port', value: '${endpoint.port}'),
              InfoRow(label: 'Joined players', value: '$connectedPlayers'),
              _AlternativeAddresses(endpoint: endpoint),
              const SizedBox(height: 8),
              _WebClientHint(isServed: state.servesWebClient),
              const SizedBox(height: 8),
              _TvScreenHint(isServed: state.servesWebClient),
              if (onOpenTvPreview != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onOpenTvPreview,
                  icon: const Icon(Icons.tv),
                  label: const Text('Open TV screen preview'),
                ),
              ],
            ] else
              InfoRow(label: 'Port', value: '${state.port}'),
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Offers the runner-up addresses when a device has more than one.
///
/// The announced address is the best *guess* — a phone on Wi-Fi and mobile data
/// reports several, and a VPN or a second network card can still outrank the
/// right one. Showing the alternatives turns a dead-end
/// `ERR_CONNECTION_TIMED_OUT` into a one-tap retry.
class _AlternativeAddresses extends StatelessWidget {
  const _AlternativeAddresses({required this.endpoint});

  final ServerEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final alternatives = endpoint.joinableAddresses
        .where((address) => address != endpoint.lanAddress)
        .toList();
    if (alternatives.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'If the LAN address times out, try:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final address in alternatives)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.content_copy, size: 14),
                  label: Text('$address:${endpoint.port}'),
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: endpoint.uriFor(address).toString()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tells the host whether guests can join straight from a browser.
///
/// The player client is bundled into the app by
/// `dart run tool/bundle_web_client.dart`; without it the host is API-only and
/// guests need the Quizmo app.
class _WebClientHint extends StatelessWidget {
  const _WebClientHint({required this.isServed});

  final bool isServed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = isServed
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isServed ? Icons.public : Icons.public_off,
          size: 16,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isServed
                ? 'Web player is hosted — guests can just open the LAN address '
                      'in a browser.'
                : 'Web player not bundled. Guests need the app, or run '
                      '`dart run tool/bundle_web_client.dart` and rebuild.',
            style: theme.textTheme.bodySmall?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// Explains how to put the spectator screen on a TV.
///
/// The TV screen is a route of the bundled web player (`/tv`), so it needs the
/// same bundle as web guests. Anything that can open a URL can show it.
class _TvScreenHint extends StatelessWidget {
  const _TvScreenHint({required this.isServed});

  final bool isServed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = isServed
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.tv, size: 16, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isServed
                ? 'TV screen: open the link above in the browser of a smart TV '
                      'or streaming stick, or cast a Chrome tab showing it. '
                      'It never shows solutions before the reveal.'
                : 'TV screen needs the bundled web player (see above).',
            style: theme.textTheme.bodySmall?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

class _CopyableUri extends StatelessWidget {
  const _CopyableUri({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied $uri')),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const Spacer(),
            Flexible(
              child: Text(
                uri.toString(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy, size: 13, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final HostServerStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (status) {
      HostServerStatus.running => (Colors.green, 'live'),
      HostServerStatus.starting => (scheme.tertiary, 'starting'),
      HostServerStatus.failed => (scheme.error, 'failed'),
      HostServerStatus.stopped => (scheme.outline, 'stopped'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Roster with per player clock quality and team assignment.
class PlayersPanel extends StatelessWidget {
  /// Creates the roster panel.
  const PlayersPanel({
    required this.game,
    required this.onAssignTeam,
    super.key,
  });

  /// Current session snapshot.
  final GameState game;

  /// Moves a player into a team, or clears the assignment with `null`.
  final void Function(String playerId, String? teamId) onAssignTeam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = game.players.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return PanelCard(
      title: 'Players (${game.connectedPlayers.length} online)',
      icon: Icons.groups_outlined,
      child: players.isEmpty
          ? const EmptyHint(
              'Waiting for clients. Share the LAN address above.',
              icon: Icons.hourglass_empty,
            )
          : Column(
              children: [
                for (final player in players)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: player.isConnected
                                ? Colors.green
                                : theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                player.isClockSynced
                                    ? 'rtt ${formatMicrosAsMillis(player.roundTripMicros)} · '
                                          'offset ${formatSignedMicrosAsMillis(player.clockOffsetMicros)}'
                                    : 'clock not synced yet',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TeamPicker(
                          teams: game.teams.values.toList(growable: false),
                          selectedTeamId: player.teamId,
                          onChanged: (teamId) =>
                              onAssignTeam(player.id, teamId),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({
    required this.teams,
    required this.selectedTeamId,
    required this.onChanged,
  });

  final List<Team> teams;
  final String? selectedTeamId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) return const SizedBox.shrink();
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: selectedTeamId,
        isDense: true,
        hint: const Text('Solo', style: TextStyle(fontSize: 12)),
        items: [
          const DropdownMenuItem<String?>(
            child: Text('Solo', style: TextStyle(fontSize: 12)),
          ),
          for (final team in teams)
            DropdownMenuItem<String?>(
              value: team.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(team.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(team.name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// The question bank with per question start buttons.
class QuestionBankPanel extends StatelessWidget {
  /// Creates the question bank panel.
  const QuestionBankPanel({
    required this.game,
    required this.canStart,
    required this.onStart,
    super.key,
  });

  /// Current session snapshot.
  final GameState game;

  /// Whether a new round may be opened right now.
  final bool canStart;

  /// Opens the round for the given question id.
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanelCard(
      title: 'Question bank',
      icon: Icons.library_books_outlined,
      child: Column(
        children: [
          for (final question in game.questionBank)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    switch (question) {
                      MultipleChoiceQuestion() => Icons.checklist,
                      BuzzerQuestion() => Icons.bolt,
                    },
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration:
                                game.completedQuestionIds.contains(question.id)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          '${question.kindLabel} · ${question.scoringRule.label}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: canStart ? () => onStart(question.id) : null,
                    child: const Text('Start'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Live view of the running round, including the latency adjusted buzzer race.
class LiveRoundPanel extends StatelessWidget {
  /// Creates the live round panel.
  const LiveRoundPanel({
    required this.state,
    required this.onJudge,
    required this.onReveal,
    required this.onLock,
    required this.onNext,
    super.key,
  });

  /// Current engine state.
  final QuizEngineState state;

  /// Accepts or rejects the spoken answer of the active player.
  final ValueChanged<bool> onJudge;

  /// Closes the round and books the points.
  final VoidCallback onReveal;

  /// Closes the grace window early.
  final VoidCallback onLock;

  /// Starts the next pending question.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = state.game;
    final round = game.round;
    final question = round.question;

    return PanelCard(
      title: 'Live round',
      icon: Icons.sensors,
      trailing: Chip(
        visualDensity: VisualDensity.compact,
        label: Text(round.status.name, style: theme.textTheme.labelSmall),
      ),
      child: question == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EmptyHint(
                  'No question on stage. Pick one from the bank.',
                  icon: Icons.play_circle_outline,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Start next pending question'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  question.prompt,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                // Polymorphic host controls: the analyzer enforces that every
                // question kind has a renderer here.
                switch (question) {
                  MultipleChoiceQuestion() => _MultipleChoiceMonitor(
                    question: question,
                    game: game,
                  ),
                  BuzzerQuestion() => _BuzzerMonitor(
                    question: question,
                    game: game,
                  ),
                },
                const SizedBox(height: 12),
                _RoundActions(
                  state: state,
                  onJudge: onJudge,
                  onReveal: onReveal,
                  onLock: onLock,
                  onNext: onNext,
                ),
                if (state.notice case final notice?) ...[
                  const SizedBox(height: 10),
                  Text(
                    notice,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _RoundActions extends StatelessWidget {
  const _RoundActions({
    required this.state,
    required this.onJudge,
    required this.onReveal,
    required this.onLock,
    required this.onNext,
  });

  final QuizEngineState state;
  final ValueChanged<bool> onJudge;
  final VoidCallback onReveal;
  final VoidCallback onLock;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final round = state.game.round;
    final activeName = state.game.activePlayer?.name;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: switch (round.status) {
        RoundStatus.idle => [
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.skip_next),
            label: const Text('Next question'),
          ),
        ],
        RoundStatus.acceptingAnswers => [
          if (round.buzzerQueue.isNotEmpty)
            FilledButton.icon(
              onPressed: onLock,
              icon: const Icon(Icons.lock_clock),
              label: const Text('Lock buzzer now'),
            ),
          OutlinedButton.icon(
            onPressed: onReveal,
            icon: const Icon(Icons.visibility),
            label: const Text('Close & reveal'),
          ),
        ],
        RoundStatus.locked => [
          FilledButton.icon(
            onPressed: () => onJudge(true),
            icon: const Icon(Icons.check),
            label: Text('${activeName ?? 'Player'} is right'),
          ),
          OutlinedButton.icon(
            onPressed: () => onJudge(false),
            icon: const Icon(Icons.close),
            label: const Text('Wrong'),
          ),
        ],
        RoundStatus.revealed => [
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.skip_next),
            label: const Text('Next question'),
          ),
        ],
      },
    );
  }
}

class _MultipleChoiceMonitor extends StatelessWidget {
  const _MultipleChoiceMonitor({required this.question, required this.game});

  final MultipleChoiceQuestion question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    final tally = <String, int>{
      for (final option in question.options) option.id: 0,
    };
    for (final answer in round.answers.values) {
      tally[answer.optionId] = (tally[answer.optionId] ?? 0) + 1;
    }
    final total = round.answers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  question.correctOptionId == option.id
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 15,
                  color: question.correctOptionId == option.id
                      ? Colors.green
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (tally[option.id] ?? 0) / total,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${tally[option.id]}', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        const SizedBox(height: 6),
        InfoRow(
          label: 'Answers received',
          value: '$total / ${game.connectedPlayers.length}',
        ),
      ],
    );
  }
}

class _BuzzerMonitor extends StatelessWidget {
  const _BuzzerMonitor({required this.question, required this.game});

  final BuzzerQuestion question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;

    if (round.buzzerQueue.isEmpty) {
      return const EmptyHint('Buzzer armed — nobody pressed yet.', icon: Icons.bolt);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Latency adjusted ranking',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < round.buzzerQueue.length; index++)
          Builder(
            builder: (context) {
              final press = round.buzzerQueue[index];
              final player = game.players[press.playerId];
              final gap = round.gapToFastest(press);
              final isActive = round.activePlayerId == press.playerId;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isActive
                      ? theme.colorScheme.tertiaryContainer.withValues(
                          alpha: 0.6,
                        )
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${index + 1}.',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        player?.name ?? press.playerId,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      index == 0
                          ? 'fastest'
                          : '+${formatMicrosAsMillis(gap.inMicroseconds)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: index == 0
                            ? Colors.green
                            : theme.colorScheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        if (round.status == RoundStatus.revealed &&
            question.expectedAnswer != null)
          InfoRow(label: 'Expected', value: question.expectedAnswer!)
        else if (question.expectedAnswer != null)
          InfoRow(label: 'Host note', value: question.expectedAnswer!),
      ],
    );
  }
}

/// Rolling log of the embedded server.
class ServerLogPanel extends StatelessWidget {
  /// Creates the log panel.
  const ServerLogPanel({required this.logs, super.key});

  /// Entries to render, newest last.
  final List<ServerLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = logs.reversed.take(12).toList(growable: false);

    return PanelCard(
      title: 'Server log',
      icon: Icons.terminal,
      child: recent.isEmpty
          ? const EmptyHint('Nothing logged yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      entry.message,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: switch (entry.level) {
                          ServerLogLevel.error => theme.colorScheme.error,
                          ServerLogLevel.warning => theme.colorScheme.tertiary,
                          ServerLogLevel.info => theme.colorScheme.outline,
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

