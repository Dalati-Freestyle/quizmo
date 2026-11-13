/// Optional technical check the host opens before (or during) a game.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../backend/server_contract.dart';
import '../../core/engine/quiz_engine_bloc.dart';
import '../../core/engine/tech_check.dart';
import '../../core/models/models.dart';
import '../common/question_media_view.dart';
import '../l10n/app_localizations.dart';
import 'host_server_cubit.dart';
import 'tech_check_settings.dart';

/// Shows the readiness findings and lets the host repeat single checks.
///
/// Nothing here changes the game: no answers, no scores, no media commands
/// to the TV. All network requests have a time limit and can be cancelled.
class TechCheckPage extends StatefulWidget {
  /// Creates the page.
  const TechCheckPage({
    required this.engine,
    required this.server,
    required this.questions,
    this.thresholds,
    this.probeTimeout = const Duration(seconds: 5),
    this.httpClient,
    super.key,
  });

  /// The running engine (roster and clock sync samples).
  final QuizEngineBloc engine;

  /// The host server (state and open sockets).
  final HostServerCubit server;

  /// Questions of the quiz for the media check.
  final List<Question> questions;

  /// Latency thresholds; `null` uses the ones stored in the settings.
  final TechCheckThresholds? thresholds;

  /// Time limit of the health request.
  final Duration probeTimeout;

  /// HTTP client (tests).
  final http.Client Function()? httpClient;

  @override
  State<TechCheckPage> createState() => _TechCheckPageState();
}

class _TechCheckPageState extends State<TechCheckPage> {
  HealthProbe _health = const HealthNotRun();
  bool _probing = false;
  http.Client? _client;
  Timer? _refresh;
  bool _tvRequired = true;
  bool _mediaRequired = true;
  final _acknowledged = <TechCheckId>{};
  late TechCheckThresholds _thresholds =
      widget.thresholds ?? TechCheckThresholds.defaultsFor(internet: _internet);

  bool get _internet => kIsWeb;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
    if (widget.thresholds == null) {
      unawaited(
        TechCheckSettingsStore.instance.load(internet: _internet).then((value) {
          if (mounted) setState(() => _thresholds = value);
        }),
      );
    }
    _refresh = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    // Leaving the check ends the request on the player devices.
    widget.server.stopDeviceCheck();
    _client?.close();
    super.dispose();
  }

  Future<void> _probe() async {
    final state = widget.server.state;
    final endpoint = state.endpoint;
    if (_internet ||
        state.status != HostServerStatus.running ||
        endpoint == null) {
      setState(() => _health = const HealthNotRun());
      return;
    }
    _client?.close();
    final client = (widget.httpClient ?? http.Client.new)();
    _client = client;
    setState(() => _probing = true);
    final address = endpoint.lanAddress;
    final watch = Stopwatch()..start();
    HealthProbe result;
    try {
      final response = await client
          .get(Uri.parse('http://$address:${endpoint.port}/api/health'))
          .timeout(widget.probeTimeout);
      result = response.statusCode == 200
          ? HealthAnswered(address: address, elapsed: watch.elapsed)
          : const HealthFailed(timedOut: false);
    } on TimeoutException {
      result = const HealthFailed(timedOut: true);
    } on Object {
      result = const HealthFailed(timedOut: false);
    }
    if (!mounted || _client != client) return;
    client.close();
    _client = null;
    setState(() {
      _health = result;
      _probing = false;
    });
  }

  void _cancelProbe() {
    _client?.close();
    _client = null;
    setState(() {
      _probing = false;
      _health = const HealthNotRun();
    });
  }

  List<TechCheckResult> _evaluate() {
    final game = widget.engine.state.game;
    return evaluateTechCheck(
      TechCheckInput(
        serverRunning: widget.server.state.status == HostServerStatus.running,
        internet: _internet,
        health: _health,
        players: game.players.values.toList(),
        connections: [
          for (final connection in widget.server.connectionHealth)
            TechCheckConnection(
              kind: switch (connection.role) {
                ConnectionRole.player => TechCheckConnectionKind.player,
                ConnectionRole.spectator => TechCheckConnectionKind.spectator,
                ConnectionRole.lobby => TechCheckConnectionKind.lobby,
              },
              playerId: connection.playerId,
              silentFor: Duration(microseconds: connection.silentForMicros),
            ),
        ],
        questions: widget.questions,
        tvRequired: _tvRequired,
        mediaRequired: _mediaRequired,
        deviceTestConfirmed: widget.server.deviceCheck?.confirmedPlayerIds,
        deviceTestScreens:
            widget.server.deviceCheck?.confirmedScreenIds.length ?? 0,
      ),
      thresholds: _thresholds,
    );
  }

  Widget? _deviceTestButton(BuildContext context) {
    if (widget.server.state.status != HostServerStatus.running) return null;
    final running = widget.server.deviceCheck != null;
    return TextButton.icon(
      key: const ValueKey('tech-check-device-test'),
      icon: Icon(running ? Icons.stop_circle_outlined : Icons.touch_app),
      label: Text(
        context.tr(running ? 'Gerätetest beenden' : 'Gerätetest starten'),
      ),
      onPressed: () => setState(() {
        if (running) {
          widget.server.stopDeviceCheck();
        } else {
          widget.server.startDeviceCheck();
        }
      }),
    );
  }

  MediaAttachment? get _testMedia {
    for (final question in widget.questions) {
      for (final media in question.media) {
        if (media is AudioAttachment ||
            (media is VideoAttachment && media.asset != null)) {
          return media;
        }
      }
    }
    return null;
  }

  Future<void> _playTest(MediaAttachment media) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Testwiedergabe')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                'Wiedergabe mit Play starten. Spielstand und TV bleiben unverändert.',
              ),
            ),
            const SizedBox(height: 12),
            QuestionMediaView(media: [media]),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Schließen')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final results = _evaluate();
    String tr(String key, [List<Object?> args = const []]) =>
        context.tr(key, args);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Technikcheck')),
        actions: [
          IconButton(
            tooltip: context.tr('Bericht kopieren'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: techCheckReport(results, tr)),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('Bericht kopiert.'))),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr(
                'Prüft Server, Verbindungen, Uhrensynchronisation, TV und Medien. Am Spielstand ändert sich nichts. Für einen echten Test mindestens ein Spieler-Gerät und den TV verbinden.',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                _internet
                    ? 'Modus: Internet-Raum über das Relay.'
                    : 'Modus: LAN-Server auf diesem Gerät.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final result in results)
              _ResultCard(
                result: result,
                acknowledged: _acknowledged.contains(result.id),
                busy: result.id == TechCheckId.hostServer && _probing,
                onRetry: result.id == TechCheckId.hostServer
                    ? _probe
                    : () => setState(() {}),
                onCancel: result.id == TechCheckId.hostServer && _probing
                    ? _cancelProbe
                    : null,
                onAcknowledge: result.status == TechCheckStatus.warning
                    ? () => setState(() {
                        if (!_acknowledged.remove(result.id)) {
                          _acknowledged.add(result.id);
                        }
                      })
                    : null,
                onToggleRequired: switch (result.id) {
                  TechCheckId.tv => () => setState(
                    () => _tvRequired = !_tvRequired,
                  ),
                  TechCheckId.media => () => setState(
                    () => _mediaRequired = !_mediaRequired,
                  ),
                  _ => null,
                },
                required: switch (result.id) {
                  TechCheckId.tv => _tvRequired,
                  TechCheckId.media => _mediaRequired,
                  _ => true,
                },
                extra: switch (result.id) {
                  TechCheckId.media when _testMedia != null => TextButton.icon(
                    key: const ValueKey('tech-check-play'),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(context.tr('Testwiedergabe')),
                    onPressed: () => _playTest(_testMedia!),
                  ),
                  TechCheckId.deviceTest => _deviceTestButton(context),
                  _ => null,
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.acknowledged,
    required this.busy,
    required this.onRetry,
    required this.required,
    this.onCancel,
    this.onAcknowledge,
    this.onToggleRequired,
    this.extra,
  });

  final TechCheckResult result;
  final bool acknowledged;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onToggleRequired;
  final bool required;
  final Widget? extra;

  static String _title(TechCheckId id) => switch (id) {
    TechCheckId.hostServer => 'Host-Server',
    TechCheckId.reachability => 'Erreichbarkeit für Gäste',
    TechCheckId.players => 'Spieler-Verbindungen',
    TechCheckId.deviceTest => 'Gerätetest (alle tippen)',
    TechCheckId.latency => 'Latenz und Uhrensynchronisation',
    TechCheckId.tv => 'TV-Verbindung',
    TechCheckId.media => 'Medien',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (result.status) {
      TechCheckStatus.pass => (Icons.check_circle, Colors.green, 'Erfolgreich'),
      TechCheckStatus.warning => (
        Icons.warning_amber,
        Colors.orange,
        'Warnung',
      ),
      TechCheckStatus.fail => (Icons.error, scheme.error, 'Fehler'),
      TechCheckStatus.notCheckable => (
        Icons.help_outline,
        scheme.outline,
        'Nicht prüfbar',
      ),
      TechCheckStatus.notRequired => (
        Icons.remove_circle_outline,
        scheme.outline,
        'Nicht erforderlich',
      ),
    };
    return Card(
      key: ValueKey('tech-check-${result.id.name}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(_title(result.id)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  acknowledged
                      ? '${context.tr(label)} · ${context.tr('bestätigt')}'
                      : context.tr(label),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.tr(result.summary, result.arguments)),
            for (final detail in result.details)
              Text('• $detail', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '→ ${context.tr(result.nextStep)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    child: Text(context.tr('Abbrechen')),
                  )
                else
                  TextButton.icon(
                    key: ValueKey('tech-check-retry-${result.id.name}'),
                    icon: const Icon(Icons.refresh),
                    label: Text(context.tr('Erneut prüfen')),
                    onPressed: onRetry,
                  ),
                if (onAcknowledge != null)
                  TextButton(
                    key: ValueKey('tech-check-ack-${result.id.name}'),
                    onPressed: onAcknowledge,
                    child: Text(
                      context.tr(
                        acknowledged
                            ? 'Bestätigung zurücknehmen'
                            : 'Warnung bestätigen',
                      ),
                    ),
                  ),
                if (onToggleRequired != null)
                  TextButton(
                    key: ValueKey('tech-check-required-${result.id.name}'),
                    onPressed: onToggleRequired,
                    child: Text(
                      context.tr(
                        required
                            ? 'Als nicht erforderlich markieren'
                            : 'Wieder prüfen',
                      ),
                    ),
                  ),
                ?extra,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
