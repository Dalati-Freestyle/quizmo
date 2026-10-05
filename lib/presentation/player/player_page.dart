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
import '../common/quizmo_logo.dart';
import '../common/jeopardy_board_view.dart';
import '../common/scoreboard_view.dart';
import '../spectator/tv_page.dart';
import 'player_session_cubit.dart';
import 'team_join_view.dart';
import 'questions/buzzer_question_view.dart';
import 'questions/new_question_views.dart';
import '../common/question_media_view.dart';
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
    return BlocConsumer<PlayerSessionCubit, PlayerSessionState>(
      listenWhen: (previous, current) =>
          current.isConnected &&
          current.error != null &&
          previous.error != current.error,
      listener: (context, state) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!))),
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const QuizmoLogo(size: 32),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    state.serverName ?? 'Join a quiz',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (state.game?.teams[state.me?.teamId] case final team?
                  when state.isConnected)
                IconButton(
                  tooltip: 'Team umbenennen: ${team.name}',
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () async {
                    final name = await showTeamNameDialog(context, team.name);
                    if (name != null && context.mounted) {
                      context.read<PlayerSessionCubit>().renameTeam(name);
                    }
                  },
                ),
              if (state.isConnected)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.star, size: 14),
                      label: Text(
                        '${state.myScore}${state.game?.poker == null ? "" : " Chips"}',
                      ),
                    ),
                  ),
                ),
              if (state.isConnected || state.isChoosingTeam)
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
                : state.isChoosingTeam
                ? TeamJoinView(
                    lobby: state.lobby!,
                    busy: state.status == QuizClientStatus.connecting,
                    error: state.error,
                    onJoin: (id) =>
                        context.read<PlayerSessionCubit>().joinTeam(teamId: id),
                    onCreate: (name) => context
                        .read<PlayerSessionCubit>()
                        .joinTeam(newTeamName: name),
                    onBack: () =>
                        context.read<PlayerSessionCubit>().disconnect(),
                  )
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
      lobbyOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = widget.state.status == QuizClientStatus.connecting;

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
                    isBusy
                        ? 'Verbindung wird hergestellt …'
                        : 'Weiter zur Teamauswahl',
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
                  title: game.poker == null ? 'Standings' : 'Pokerchips',
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
    if (state.game?.poker case final poker? when poker.betting) {
      return PokerWagerView(
        key: ValueKey(question.id),
        state: state,
        onWager: cubit.placePokerWager,
      );
    }

    // Exhaustive switch over the sealed `Question` hierarchy: adding a new
    // question type makes this line fail to compile until it has a renderer.
    final enabled =
        state.roundStatus.acceptsInput && state.lastSubmittedOptionId == null;
    final input = switch (question) {
      MultipleChoiceQuestion() => MultipleChoiceQuestionView(
        question: question,
        status: state.roundStatus,
        selectedOptionId: state.lastSubmittedOptionId,
        onSelect: cubit.choose,
      ),
      ShortAnswerQuestion() => ShortAnswerQuestionView(
        key: ValueKey(
          '${question.id}-${state.game?.round.startedAtHostMicros}',
        ),
        question: question,
        enabled: enabled,
        onSubmit: (value) => cubit.submit(
          (id, timestamp, offset) => ShortAnswer(
            playerId: id,
            questionId: question.id,
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            text: value,
          ),
        ),
      ),
      OrderingQuestion() => OrderingQuestionView(
        key: ValueKey(
          '${question.id}-${state.game?.round.startedAtHostMicros}',
        ),
        question: question,
        enabled: enabled,
        onSubmit: (value) => cubit.submit(
          (id, timestamp, offset) => OrderingAnswer(
            playerId: id,
            questionId: question.id,
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            itemIds: value,
          ),
        ),
      ),
      MatchingQuestion() => MatchingQuestionView(
        key: ValueKey(
          '${question.id}-${state.game?.round.startedAtHostMicros}',
        ),
        question: question,
        enabled: enabled,
        onSubmit: (value) => cubit.submit(
          (id, timestamp, offset) => MatchingAnswer(
            playerId: id,
            questionId: question.id,
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            pairs: value,
          ),
        ),
      ),
      EstimationQuestion() => EstimationQuestionView(
        key: ValueKey(
          '${question.id}-${state.game?.round.startedAtHostMicros}',
        ),
        question: question,
        enabled: enabled,
        onSubmit: (value) => cubit.submit(
          (id, timestamp, offset) => EstimationAnswer(
            playerId: id,
            questionId: question.id,
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            value: value,
          ),
        ),
      ),
      TrueFalseQuestion() => TrueFalseQuestionView(
        key: ValueKey(
          '${question.id}-${state.game?.round.startedAtHostMicros}',
        ),
        question: question,
        enabled: enabled,
        onSubmit: (value) => cubit.submit(
          (id, timestamp, offset) => TrueFalseAnswer(
            playerId: id,
            questionId: question.id,
            clientTimestampMicros: timestamp,
            clockOffsetMicros: offset,
            value: value,
          ),
        ),
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

    final view = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question is! MultipleChoiceQuestion &&
            question is! BuzzerQuestion) ...[
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (state.lastSubmittedOptionId != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Antwort gesendet'),
            ),
          const SizedBox(height: 24),
        ],
        if (question.media.isNotEmpty) ...[
          QuestionMediaView(media: question.media, baseUri: cubit.mediaBaseUri),
          const SizedBox(height: 16),
        ],
        input,
        if (state.roundStatus == RoundStatus.revealed) ...[
          const SizedBox(height: 24),
          if (question is! MultipleChoiceQuestion &&
              question is! BuzzerQuestion)
            Text('Lösung: ${question.solutionLabel}'),
          QuestionMediaView(
            media: question.solutionMedia,
            baseUri: cubit.mediaBaseUri,
          ),
        ],
      ],
    );
    if (state.game?.poker case final poker?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${poker.chips[state.me?.teamId] ?? 0} Chips · Einsatz: ${poker.wagers[state.me?.teamId] ?? 0}',
          ),
          if (!state.mayAnswerPoker && state.roundStatus.acceptsInput)
            const Text('Dein Team setzt aus oder wurde bereits gewertet.'),
          const SizedBox(height: 12),
          AbsorbPointer(absorbing: !state.mayAnswerPoker, child: view),
        ],
      );
    }
    if (jeopardy == null || !jeopardy.hasActiveQuestion) return view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlayerJeopardyBanner(state: state, jeopardy: jeopardy),
        const SizedBox(height: 16),
        view,
        if (state.roundStatus == RoundStatus.revealed) ...[
          const SizedBox(height: 24),
          _PlayerBoard(state: state, jeopardy: jeopardy),
        ],
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
    final mayPick =
        state.isConnected &&
        (jeopardy.currentTeamId == null ||
            state.me?.teamId == jeopardy.currentTeamId);
    final score = game.teamScores[jeopardy.currentTeamId] ?? 0;
    final maxWager = score > jeopardy.board.highestRowPoints
        ? score
        : jeopardy.board.highestRowPoints;
    final cubit = context.read<PlayerSessionCubit>();

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
        if (isDailyDouble && mayPick)
          DailyDoubleWagerView(
            key: ValueKey(jeopardy.pendingDailyDoubleId),
            maxWager: maxWager,
            onWager: (wager) => cubit.placeDailyDoubleWager(
              jeopardy.pendingDailyDoubleId!,
              wager,
            ),
          ),
        JeopardyBoardView(
          board: jeopardy.board,
          completedQuestionIds: game.completedQuestionIds,
          winners: game.questionWinners,
          highlightQuestionId: jeopardy.pendingDailyDoubleId,
          onSelect: mayPick && !isDailyDouble ? cubit.selectJeopardyCell : null,
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

class PokerWagerView extends StatefulWidget {
  const PokerWagerView({required this.state, required this.onWager, super.key});
  final PlayerSessionState state;
  final ValueChanged<int> onWager;
  @override
  State<PokerWagerView> createState() => _PokerWagerViewState();
}

class _PokerWagerViewState extends State<PokerWagerView> {
  final _controller = TextEditingController(text: '10');
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final poker = state.game!.poker!;
    final team = state.me?.teamId;
    final chips = poker.chips[team] ?? 0;
    final wager = poker.wagers[team];
    final value = int.tryParse(_controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.question!.prompt,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text('Pokerchips · $chips Chips verfügbar'),
        const SizedBox(height: 16),
        if (team == null)
          const Text('Der Quizmaster muss dich einem Team zuweisen.')
        else if (wager != null)
          Text('Teameinsatz: $wager Chips. Warte auf die Antwortphase.')
        else if (chips == 0)
          const Text('Keine Chips mehr. Dein Team setzt aus.')
        else ...[
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Einsatz (0–$chips)',
              helperText: 'Richtig: doppelte Auszahlung. Falsch: Einsatz verloren. 0 = aussetzen.',
              helperMaxLines: 4,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: value != null && value >= 0 && value <= chips
                ? () => widget.onWager(value)
                : null,
            child: const Text('Teameinsatz bestätigen'),
          ),
          TextButton(
            onPressed: () => widget.onWager(chips),
            child: const Text('All-in'),
          ),
        ],
      ],
    );
  }
}

class DailyDoubleWagerView extends StatefulWidget {
  const DailyDoubleWagerView({
    required this.maxWager,
    required this.onWager,
    super.key,
  });
  final int maxWager;
  final ValueChanged<int> onWager;
  @override
  State<DailyDoubleWagerView> createState() => _DailyDoubleWagerViewState();
}

class _DailyDoubleWagerViewState extends State<DailyDoubleWagerView> {
  late final controller = TextEditingController(text: '${widget.maxWager}');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wager = int.tryParse(controller.text.trim());
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Daily Double: Einsatz (1–${widget.maxWager})',
              helperText:
                  'Bei einer falschen Antwort verliert dein Team den Einsatz.',
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: wager != null && wager >= 1 && wager <= widget.maxWager
                ? () => widget.onWager(wager)
                : null,
            child: const Text('Einsatz bestätigen & Frage öffnen'),
          ),
        ],
      ),
    );
  }
}
