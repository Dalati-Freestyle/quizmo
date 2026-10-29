import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/engine/quiz_engine_bloc.dart';
import '../../../core/models/models.dart';
import '../../../core/net/quiz_client.dart';
import '../../../core/simulation/bot_decisions.dart';
import '../../../core/simulation/preview_session.dart';
import '../../common/adaptive_layout.dart';
import '../../common/scoreboard_view.dart';
import '../../l10n/app_localizations.dart';
import '../../player/player_page.dart';
import '../../player/player_session_cubit.dart';
import '../../spectator/spectator_session_cubit.dart';
import '../../spectator/tv_page.dart';
import '../dashboard_panels.dart';

class QuizPreviewPage extends StatefulWidget {
  const QuizPreviewPage({required this.quiz, this.seed, super.key});
  final Quiz quiz;
  final int? seed;

  @override
  State<QuizPreviewPage> createState() => _QuizPreviewPageState();
}

class _QuizPreviewPageState extends State<QuizPreviewPage> {
  late PreviewSession _session;
  late final TextEditingController _seed;
  late final Timer _ticker;
  PlayerSessionCubit? _player;
  String? _selectedPlayer;
  int _view = 0;
  bool _running = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed ?? Random().nextInt(0x7fffffff);
    _seed = TextEditingController(text: '$seed');
    _session = PreviewSession(widget.quiz, seed: seed);
    _selectedPlayer = _session.addParticipant(name: 'Test');
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_running && !_busy) {
        unawaited(_advance(const Duration(milliseconds: 50)));
      }
    });
  }

  Future<void> _advance(Duration duration) async {
    if (_busy) return;
    _busy = true;
    try {
      await _session.advance(duration);
    } on Object catch (error) {
      _error = '$error';
      _running = false;
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _restart({bool roundOnly = false}) async {
    final seed = int.tryParse(_seed.text);
    if (_busy || (!roundOnly && seed == null)) return;
    setState(() => _busy = true);
    PreviewSession? replacement;
    try {
      final previous = _session;
      final roster = previous.participants;
      final currentPlayers = previous.engine.state.game.players;
      replacement = roundOnly
          ? previous.replayRound()
          : PreviewSession(widget.quiz, seed: seed!);
      replacement.setBotsEnabled(previous.botsEnabled);
      await _player?.close();
      _player = null;
      await previous.close();
      if (!mounted) {
        await replacement.close();
        return;
      }
      _session = replacement;
      if (!roundOnly) {
        final teamIds = <String, String>{
          for (final team in widget.quiz.teams) team.id: team.id,
        };
        for (final participant in roster) {
          final player =
              currentPlayers[participant.player.id] ?? participant.player;
          final oldTeam = player.teamId;
          final id = replacement.addParticipant(
            name: player.name,
            bot: participant.bot,
            teamId: teamIds[oldTeam],
            ownTeam: oldTeam != null && !teamIds.containsKey(oldTeam),
          );
          await replacement.flush();
          if (!mounted) return;
          if (oldTeam != null) {
            teamIds[oldTeam] =
                replacement.engine.state.game.players[id]!.teamId!;
          }
        }
      }
      await replacement.flush();
      if (!mounted) return;
      _selectedPlayer = replacement.participants.firstOrNull?.player.id;
      _error = null;
    } on Object catch (error) {
      if (replacement != null && !identical(replacement, _session)) {
        await replacement.close();
      }
      _error = '$error';
      _running = false;
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _replayRound() => _restart(roundOnly: true);

  Future<void> _addParticipant() async {
    final participant = await showDialog<_ParticipantInput>(
      context: context,
      builder: (_) => _ParticipantDialog(
        teams: _session.engine.state.game.teams.values.toList(),
      ),
    );
    if (participant == null || !mounted) return;
    final id = _session.addParticipant(
      name: participant.name,
      bot: participant.bot,
      teamId: participant.teamId,
      ownTeam: participant.ownTeam,
    );
    await _advance(Duration.zero);
    if (mounted) setState(() => _selectedPlayer ??= id);
  }

  void _selectPlayer(String? id) {
    if (id == _selectedPlayer) return;
    unawaited(_player?.close());
    _player = null;
    setState(() => _selectedPlayer = id);
  }

  @override
  void dispose() {
    _ticker.cancel();
    _seed.dispose();
    unawaited(_player?.close());
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<QuizEngineBloc, QuizEngineState>(
    bloc: _session.engine,
    builder: (context, state) {
      final roster = _session.participants;
      return Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Preview · {0}', [widget.quiz.name])),
          actions: [
            if (_view == 0)
              PopupMenuButton<GameMode>(
                tooltip: context.tr('Game mode'),
                icon: const Icon(Icons.tune),
                onSelected: (mode) => _session.send(ChangeGameModeEvent(mode)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: const SoloMode(),
                    child: Text(context.tr('Solo scoring')),
                  ),
                  PopupMenuItem(
                    value: const TeamMode(),
                    child: Text(context.tr('Team scoring (shared buzzer)')),
                  ),
                  PopupMenuItem(
                    value: const TeamMode(sharedBuzzer: false),
                    child: Text(
                      context.tr('Team scoring (individual buzzers)'),
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  context.tr(
                    'Isolated preview: unsaved draft, no room, no saved scores.',
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.35,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(context.tr('Host')),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(context.tr('Player')),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text(context.tr('TV')),
                            ),
                          ],
                          selected: {_view},
                          onSelectionChanged: (value) =>
                              setState(() => _view = value.single),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _addParticipant,
                          icon: const Icon(Icons.person_add_alt),
                          label: Text(context.tr('Add test participant')),
                        ),
                        IconButton(
                          tooltip: context.tr(
                            _running ? 'Pause simulation' : 'Resume simulation',
                          ),
                          onPressed: () => setState(() => _running = !_running),
                          icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                        ),
                        TextButton(
                          onPressed: _running || _busy
                              ? null
                              : () => _advance(const Duration(seconds: 1)),
                          child: Text(context.tr('Step +1 s')),
                        ),
                        Text(
                          context.tr('Simulation: {0} ms', [
                            _session.clock.nowMicros ~/ 1000,
                          ]),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _seed,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('Seed'),
                              errorText: int.tryParse(_seed.text) == null
                                  ? context.tr('Enter an integer.')
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy || int.tryParse(_seed.text) == null
                              ? null
                              : _restart,
                          child: Text(context.tr('Restart preview')),
                        ),
                        TextButton(
                          onPressed: _busy || !_session.canReplayRound
                              ? null
                              : _replayRound,
                          child: Text(context.tr('Replay round')),
                        ),
                        FilterChip(
                          label: Text(context.tr('Automatic bots')),
                          selected: _session.botsEnabled,
                          onSelected: (enabled) =>
                              setState(() => _session.setBotsEnabled(enabled)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_view == 1)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedPlayer,
                    hint: Text(context.tr('Add test participant')),
                    items: [
                      for (final participant in roster)
                        DropdownMenuItem(
                          value: participant.player.id,
                          child: Text(
                            state.game.players[participant.player.id]?.name ??
                                participant.player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _selectPlayer,
                  ),
                ),
              const Divider(),
              Expanded(
                child: switch (_view) {
                  0 => _host(state),
                  1 => _playerView(),
                  _ => _tvView(),
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _playerView() {
    final id = _selectedPlayer;
    if (id == null) {
      return Center(child: Text(context.tr('Add test participant')));
    }
    if (_player?.state.playerId != id) {
      unawaited(_player?.close());
      _player = PlayerSessionCubit.local(
        playerId: id,
        initialGame: _session.guestGame,
        snapshots: _session.guestSnapshots,
        send: _session.send,
        now: () => _session.clock.nowMicros,
      );
    }
    return BlocProvider.value(value: _player!, child: const LocalPlayerBoard());
  }

  Widget _tvView() => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: FittedBox(
          child: SizedBox(
            width: kTvCanvasWidth,
            height: kTvCanvasHeight,
            child: TvScreen(
              state: SpectatorSessionState(
                status: QuizClientStatus.connected,
                serverName: context.tr('Preview'),
                game: _session.guestGame.copyWith(
                  hostTimeMicros: _session.clock.nowMicros,
                ),
                snapshotReceivedAt: DateTime.now(),
                extrapolateTime: false,
              ),
              joinUri: Uri.parse('https://preview.invalid'),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _host(QuizEngineState state) {
    final game = state.game;
    final engine = _session.engine;
    return AdaptivePanelGrid(
      panels: [
        if (!game.isStarted)
          PanelCard(
            title: context.tr('Quiz starten'),
            icon: Icons.play_arrow,
            child: FilledButton(
              onPressed: () => _session.send(const StartGameEvent()),
              child: Text(context.tr('Quiz jetzt starten')),
            ),
          ),
        LiveRoundPanel(
          state: state,
          onJudge: (correct) =>
              _session.send(JudgeBuzzerEvent(wasCorrect: correct)),
          onJudgeAnswer: _session.send,
          onReveal: () => _session.send(const RevealRoundEvent()),
          onLock: () => _session.send(const LockBuzzerEvent()),
          onNext: () => _session.send(const NextQuestionEvent()),
          onCloseRound: () => _session.send(const CloseRoundEvent()),
          onReopenBuzzer: () => _session.send(const ReopenBuzzerEvent()),
          onReopenBuzzerForAll: () =>
              _session.send(const ReopenBuzzerEvent(forAll: true)),
          onEndRound: () => _session.send(const EndRoundEvent()),
        ),
        if (game.poker case final poker?)
          PanelCard(
            title: context.tr('Pokerchips'),
            icon: Icons.casino_outlined,
            child: Column(
              children: [
                for (final team in game.teams.values)
                  Text(
                    '${team.name}: ${poker.chips[team.id]} · ${poker.wagers[team.id] ?? 0}',
                  ),
                if (poker.betting)
                  FilledButton(
                    onPressed: () =>
                        _session.send(const OpenPokerAnswersEvent()),
                    child: Text(
                      context.tr('Einsätze schließen & Antworten öffnen'),
                    ),
                  ),
              ],
            ),
          ),
        if (game.jeopardy case final jeopardy?)
          JeopardyBoardPanel(
            game: game,
            jeopardy: jeopardy,
            canPick:
                game.isStarted &&
                state.canStartRound &&
                jeopardy.pendingPickQuestionId == null,
            maxWager: engine.maxDailyDoubleWager(game),
            onSelect: (id) => _session.send(SelectJeopardyCellEvent(id)),
            onPlaceWager: (wager) =>
                _session.send(PlaceDailyDoubleWagerEvent(wager)),
            onSetTurn: (id) => _session.send(SetJeopardyTurnEvent(id)),
            onSetOrder: (ids) => _session.send(SetJeopardyOrderEvent(ids)),
          ),
        if (game.jeopardy case final board?
            when board.pendingPickQuestionId != null)
          PanelCard(
            title: context.tr('Fragenauswahl bestätigen'),
            icon: Icons.grid_view,
            child: Wrap(
              spacing: 8,
              children: [
                Text(
                  board.board.categoryNameOf(board.pendingPickQuestionId!) ??
                      '',
                ),
                for (final accepted in [true, false])
                  TextButton(
                    onPressed: () => _session.send(
                      ConfirmQuestionPickEvent(
                        questionId: board.pendingPickQuestionId!,
                        playerId: board.pendingPickPlayerId!,
                        accepted: accepted,
                      ),
                    ),
                    child: Text(
                      context.tr(accepted ? 'Bestätigen' : 'Ablehnen'),
                    ),
                  ),
              ],
            ),
          ),
        if (game.jeopardy == null)
          QuestionBankPanel(
            game: game,
            canStart: game.isStarted && state.canStartRound,
            onStart: (id) => _session.send(StartRoundEvent(id)),
          ),
        PanelCard(
          title: context.tr('Test participants'),
          icon: Icons.smart_toy_outlined,
          child: Column(
            children: [
              for (final participant in _session.participants)
                ListTile(
                  title: Text(
                    game.players[participant.player.id]?.name ??
                        participant.player.name,
                  ),
                  subtitle: Text(
                    participant.bot == null
                        ? context.tr('Manual input')
                        : context.tr('Bot: {0}% · {1}–{2} ms', [
                            (participant.bot!.accuracy * 100).round(),
                            participant.bot!.minDelayMs,
                            participant.bot!.maxDelayMs,
                          ]),
                  ),
                  trailing: IconButton(
                    tooltip: context.tr('Remove test participant'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final id = participant.player.id;
                      _session.removeParticipant(id);
                      if (_selectedPlayer == id) {
                        _selectPlayer(
                          _session.participants.firstOrNull?.player.id,
                        );
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        PlayersPanel(
          game: game,
          onAssignTeam: (id, team) =>
              _session.send(AssignTeamEvent(playerId: id, teamId: team)),
          onSetOrder: state.canStartRound
              ? (ids) => _session.send(SetPlayerOrderEvent(ids))
              : null,
        ),
        PanelCard(
          title: context.tr('Scoreboard'),
          icon: Icons.leaderboard_outlined,
          child: ScoreboardView(game: game),
        ),
        PanelCard(
          title: context.tr('Medienwiedergabe'),
          icon: Icons.live_tv,
          child: Wrap(
            children: [
              for (final action in TvMediaAction.values)
                IconButton(
                  tooltip: context.tr(switch (action) {
                    TvMediaAction.play => 'Abspielen',
                    TvMediaAction.pause => 'Pause',
                    TvMediaAction.restart => 'Neu starten',
                  }),
                  onPressed: () => _session.send(ControlTvMediaEvent(action)),
                  icon: Icon(switch (action) {
                    TvMediaAction.play => Icons.play_arrow,
                    TvMediaAction.pause => Icons.pause,
                    TvMediaAction.restart => Icons.replay,
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _ParticipantInput {
  const _ParticipantInput(this.name, this.bot, this.teamId, this.ownTeam);
  final String name;
  final BotSettings? bot;
  final String? teamId;
  final bool ownTeam;
}

class _ParticipantDialog extends StatefulWidget {
  const _ParticipantDialog({required this.teams});
  final List<Team> teams;

  @override
  State<_ParticipantDialog> createState() => _ParticipantDialogState();
}

class _ParticipantDialogState extends State<_ParticipantDialog> {
  final _name = TextEditingController(text: 'Bot');
  final _min = TextEditingController(text: '300');
  final _max = TextEditingController(text: '1800');
  bool _bot = true;
  double _accuracy = 0.7;
  String _team = '';

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final min = int.tryParse(_min.text);
    final max = int.tryParse(_max.text);
    final validRange =
        min != null && max != null && min >= 0 && max >= min && max <= 3600000;
    return AlertDialog(
      title: Text(context.tr('Add test participant')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                maxLength: 60,
                decoration: InputDecoration(labelText: context.tr('Name')),
                onChanged: (_) => setState(() {}),
              ),
              SwitchListTile(
                title: Text(context.tr('Automatic bot')),
                value: _bot,
                onChanged: (value) => setState(() => _bot = value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _team,
                decoration: InputDecoration(labelText: context.tr('Team')),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.tr('Automatic / solo')),
                  ),
                  DropdownMenuItem(
                    value: 'new',
                    child: Text(context.tr('Own test team')),
                  ),
                  for (final team in widget.teams)
                    DropdownMenuItem(value: team.id, child: Text(team.name)),
                ],
                onChanged: (value) => setState(() => _team = value!),
              ),
              if (_bot) ...[
                const SizedBox(height: 16),
                Text(
                  context.tr('Target accuracy: {0}%', [
                    (_accuracy * 100).round(),
                  ]),
                ),
                Slider(
                  value: _accuracy,
                  divisions: 100,
                  label: '${(_accuracy * 100).round()}%',
                  onChanged: (value) => setState(() => _accuracy = value),
                ),
                Text(
                  context.tr(
                    'Probability per answer, not a guaranteed quiz score.',
                  ),
                ),
                TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Minimum delay (ms)'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Maximum delay (ms)'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (!validRange)
                  Text(
                    context.tr(
                      'Delay range must satisfy 0 ≤ min ≤ max ≤ 3600000 ms.',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || (_bot && !validRange)
              ? null
              : () => Navigator.pop(
                  context,
                  _ParticipantInput(
                    _name.text.trim(),
                    _bot
                        ? BotSettings(
                            accuracy: _accuracy,
                            minDelayMs: min!,
                            maxDelayMs: max!,
                          )
                        : null,
                    _team == '' || _team == 'new' ? null : _team,
                    _team == 'new',
                  ),
                ),
          child: Text(context.tr('Add')),
        ),
      ],
    );
  }
}
