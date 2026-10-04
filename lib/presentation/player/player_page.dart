/// The player shell: join form and live game view in one route.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/models.dart';
import '../../core/net/quiz_client.dart';
import '../../core/sync/clock.dart';
import '../../backend/server_launcher.dart' show defaultServerPort;
import '../common/adaptive_layout.dart';
import '../common/jeopardy_board_view.dart';
import '../common/scoreboard_view.dart';
import '../spectator/tv_page.dart';
import 'player_session_cubit.dart';
import 'questions/buzzer_question_view.dart';
import 'questions/multiple_choice_question_view.dart';

/// Player facing screen.
///
/// The join form and the game board share one route so that a reconnect does
/// not tear down the navigation stack.
class PlayerPage extends StatelessWidget {
  /// Creates the player screen, optionally pre-filled with [initialHostUri].
  const PlayerPage({this.initialHostUri, super.key});

  /// Host address to pre-fill, for example when joining the local host.
  final Uri? initialHostUri;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PlayerSessionCubit>(
      create: (_) => PlayerSessionCubit(),
      child: _PlayerView(initialHostUri: initialHostUri),
    );
  }
}

class _PlayerView extends StatelessWidget {
  const _PlayerView({this.initialHostUri});

  final Uri? initialHostUri;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerSessionCubit, PlayerSessionState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(state.serverName ?? 'Join a quiz'),
            actions: [
              if (state.isConnected)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.star, size: 14),
                      label: Text('${state.myScore}'),
                    ),
                  ),
                ),
              if (state.isConnected)
                IconButton(
                  tooltip: 'Leave',
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      context.read<PlayerSessionCubit>().disconnect(),
                ),
            ],
          ),
          body: SafeArea(
            child: state.isConnected
                ? _GameBoard(state: state)
                : _JoinForm(state: state, initialHostUri: initialHostUri),
          ),
        );
      },
    );
  }
}

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.state, this.initialHostUri});

  final PlayerSessionState state;
  final Uri? initialHostUri;

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  late final TextEditingController _hostController;
  late final TextEditingController _nameController;
  final _formKey = GlobalKey<FormState>();
  final _hostKey = GlobalKey<FormFieldState<String>>();
  String? _teamId;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: _defaultHost());
    _nameController = TextEditingController();
  }

  /// Guesses a sensible default host address.
  ///
  /// When the page was served by the embedded host itself — the normal case for
  /// a guest who just opened the LAN address — its own origin *is* the host,
  /// port included. `?host=` still wins so a ready-made join link can point at
  /// a different device, and a dev server on port 5xxx falls back to the
  /// default host port.
  String _defaultHost() {
    if (widget.initialHostUri != null) {
      return widget.initialHostUri.toString();
    }
    final fromQuery = Uri.base.queryParameters['host'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (kIsWeb) {
      return Uri.base.port == defaultServerPort
          ? Uri.base.origin
          : 'http://${Uri.base.host}:$defaultServerPort';
    }
    return 'http://127.0.0.1:$defaultServerPort';
  }

  @override
  void dispose() {
    _hostController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Opens the read-only TV view for the entered host instead of joining.
  ///
  /// Only the host field is validated: a spectator needs neither a name nor a
  /// team, and never shows up in the roster.
  void _spectate() {
    final uri = Uri.tryParse(_hostController.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _hostKey.currentState?.validate();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TvPage(hostUri: uri)));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uri = Uri.parse(_hostController.text.trim());
    await context.read<PlayerSessionCubit>().connect(
      baseUri: uri,
      name: _nameController.text.trim(),
      teamId: _teamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = widget.state.status == QuizClientStatus.connecting;
    // The team roster is only known after the first snapshot, so the join form
    // offers the two demo teams the sample quiz ships with.
    const teams = {'team-red': 'Red Foxes', 'team-blue': 'Blue Whales'};

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Join a session',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter the address shown on the quizmaster dashboard.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: _hostKey,
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Host address',
                    prefixIcon: Icon(Icons.lan_outlined),
                    helperText: 'for example http://192.168.1.42:8080',
                  ),
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
                      return 'Enter a full URL including http://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Pick a name' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _teamId,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(child: Text('Solo')),
                    for (final entry in teams.entries)
                      DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() => _teamId = value),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isBusy ? null : _submit,
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    isBusy ? 'Syncing clock…' : 'Connect and sync clock',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : _spectate,
                  icon: const Icon(Icons.tv),
                  label: const Text('Just watch (TV view)'),
                ),
                if (widget.state.error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameBoard extends StatelessWidget {
  const _GameBoard({required this.state});

  final PlayerSessionState state;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    final isWide = formFactorOf(context).isWide;

    final stage = Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(child: _QuestionStage(state: state)),
        ),
      ),
    );

    if (game == null || !isWide) return stage;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: stage),
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PanelCard(
                  title: 'Standings',
                  icon: Icons.leaderboard_outlined,
                  child: ScoreboardView(
                    game: game,
                    highlightPlayerId: state.playerId,
                  ),
                ),
                const SizedBox(height: 16),
                PanelCard(
                  title: 'Connection',
                  icon: Icons.wifi_tethering,
                  child: Column(
                    children: [
                      InfoRow(
                        label: 'Latency',
                        value: state.roundTripMicros == 0
                            ? '—'
                            : formatMicrosAsMillis(state.roundTripMicros ~/ 2),
                      ),
                      InfoRow(
                        label: 'Clock offset',
                        value: formatSignedMicrosAsMillis(
                          state.clockOffsetMicros,
                        ),
                      ),
                      InfoRow(label: 'Player', value: state.me?.name ?? '—'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionStage extends StatelessWidget {
  const _QuestionStage({required this.state});

  final PlayerSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = state.question;
    final jeopardy = state.game?.jeopardy;

    if (question == null && jeopardy != null) {
      return _PlayerBoard(state: state, jeopardy: jeopardy);
    }

    if (question == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Waiting for the quizmaster…',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            state.roundTripMicros == 0
                ? 'Clock sync pending'
                : 'Clock synced · latency '
                      '${formatMicrosAsMillis(state.roundTripMicros ~/ 2)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      );
    }

    final cubit = context.read<PlayerSessionCubit>();

    // Exhaustive switch over the sealed `Question` hierarchy: adding a new
    // question type makes this line fail to compile until it has a renderer.
    final view = switch (question) {
      MultipleChoiceQuestion() => MultipleChoiceQuestionView(
        question: question,
        status: state.roundStatus,
        selectedOptionId: state.lastSubmittedOptionId,
        onSelect: cubit.choose,
      ),
      BuzzerQuestion() => BuzzerQuestionView(
        question: question,
        round: state.game?.round ?? RoundState.idle,
        playerId: state.playerId,
        hasBuzzed: state.hasBuzzed,
        onBuzz: cubit.buzz,
        clockOffsetMicros: state.clockOffsetMicros,
        roundTripMicros: state.roundTripMicros,
      ),
    };

    if (jeopardy == null || !jeopardy.hasActiveQuestion) return view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlayerJeopardyBanner(state: state, jeopardy: jeopardy),
        const SizedBox(height: 16),
        view,
      ],
    );
  }
}

/// The board between two questions, as seen on a player's phone.
class _PlayerBoard extends StatelessWidget {
  const _PlayerBoard({required this.state, required this.jeopardy});

  final PlayerSessionState state;
  final JeopardyState jeopardy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = state.game!;
    final picker = game.teams[jeopardy.currentTeamId];
    final isDailyDouble = jeopardy.pendingDailyDoubleId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isDailyDouble
              ? 'Daily Double! ${picker?.name ?? 'The picking team'} '
                    'is placing a wager…'
              : picker == null
              ? 'Waiting for the next question…'
              : '${picker.name} picks the next question',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        JeopardyBoardView(
          board: jeopardy.board,
          completedQuestionIds: game.completedQuestionIds,
          highlightQuestionId: jeopardy.pendingDailyDoubleId,
        ),
      ],
    );
  }
}

/// Says what a board question is worth and whether this player may answer.
class _PlayerJeopardyBanner extends StatelessWidget {
  const _PlayerJeopardyBanner({required this.state, required this.jeopardy});

  final PlayerSessionState state;
  final JeopardyState jeopardy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final game = state.game!;
    final questionId = game.round.question?.id;
    final category = questionId == null
        ? null
        : jeopardy.board.categoryNameOf(questionId);
    final picker = game.teams[jeopardy.currentTeamId];
    final mayAnswer = jeopardy.mayAnswer(state.me?.teamId);
    final isOpen = state.roundStatus.acceptsInput;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (category != null) Chip(label: Text(category)),
            Chip(
              avatar: jeopardy.activeIsDailyDouble
                  ? const Icon(Icons.star, size: 16)
                  : null,
              label: Text(
                '${jeopardy.activePoints} pts'
                '${jeopardy.activeIsDailyDouble ? ' · Daily Double' : ''}',
              ),
            ),
          ],
        ),
        if (isOpen && picker != null) ...[
          const SizedBox(height: 8),
          Text(
            mayAnswer
                ? (jeopardy.isStealRound
                      ? 'Steal! Your team may answer now.'
                      : 'Your team answers.')
                : (jeopardy.isStealRound
                      ? 'Steal round: only the other teams answer.'
                      : '${picker.name} answers first.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: mayAnswer ? scheme.primary : scheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}
