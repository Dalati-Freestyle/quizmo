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
import '../../l10n/app_localizations.dart';
import '../../player/player_page.dart';
import '../../player/player_session_cubit.dart';
import '../../spectator/spectator_session_cubit.dart';
import '../../spectator/tv_page.dart';
import '../game_sections.dart';
import '../layout/dashboard_section_view.dart';

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
          actions: [if (_view == 0) GameModeMenu(engine: _session.engine)],
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

  /// The host view of the preview: exactly the game sections of the real
  /// admin view ([buildGameSections]) in the stored layout, plus the test
  /// participants of the simulation.
  Widget _host(QuizEngineState state) {
    final game = state.game;
    final engine = _session.engine;
    return JeopardyPickConfirmation(
      engine: engine,
      child: DashboardSectionGrid(
        leading: [
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
        ],
        sections: buildGameSections(
          context,
          engine: engine,
          engineState: state,
          quizName: widget.quiz.name,
        ),
      ),
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
