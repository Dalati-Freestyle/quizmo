/// The spectator ("TV") screen.
///
/// A read-only, lean-back view of the running session for a big display: a
/// smart TV browser, a streaming stick or a casted browser tab. It subscribes
/// to the host as a `WatchRequest` spectator, so it never appears in the player
/// roster and can never influence a round, and it only ever sees the redacted
/// snapshot — the quizmaster keeps every confidential control on the host.
///
/// ## Layout
///
/// The screen is composed on a fixed 1920×1080 canvas that is scaled to fit
/// the display (letterboxed). That keeps type sizes, spacing and the amount of
/// content identical on a 1080p TV, a 4K panel and a small preview window, and
/// guarantees readability from the sofa: no text on the canvas is below 22 px,
/// which is ~2 cm on a 55" TV.
///
/// ## Shortcuts
///
/// * `T` toggles between dark (default) and light colours,
/// * `R` reconnects immediately,
/// * `Esc` closes the preview when it was opened from the host dashboard.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../backend/server_launcher.dart' show defaultServerPort;
import '../../core/models/models.dart';
import '../../core/sync/clock.dart';
import '../app.dart';
import '../common/jeopardy_board_view.dart';
import 'spectator_session_cubit.dart';
import 'tv_launch.dart';
import 'tv_standings.dart';

/// Width of the logical design canvas.
const double kTvCanvasWidth = 1920;

/// Height of the logical design canvas.
const double kTvCanvasHeight = 1080;

/// Spectator screen for large displays.
class TvPage extends StatelessWidget {
  /// Creates the TV screen.
  ///
  /// [hostUri] overrides the host address; by default it is the origin that
  /// served the page (the normal case on a TV), `?host=` or the default port
  /// on this device. [joinUri] is the address players are told to open and
  /// defaults to [hostUri]; the dashboard preview passes the LAN address here
  /// because its own connection goes through loopback.
  const TvPage({this.hostUri, this.joinUri, this.brightness, super.key});

  /// Address of the host to watch.
  final Uri? hostUri;

  /// Address printed on the lobby screen for players.
  final Uri? joinUri;

  /// Initial colour scheme; `?theme=light|dark` is used when `null`.
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final host = hostUri ?? _defaultHostUri();
    return BlocProvider<SpectatorSessionCubit>(
      create: (_) {
        final cubit = SpectatorSessionCubit(baseUri: host);
        unawaited(cubit.start());
        return cubit;
      },
      child: _TvView(
        joinUri: joinUri ?? host,
        initialBrightness: brightness ?? tvBrightnessFor(Uri.base),
      ),
    );
  }

  /// Guesses the host: `?host=` wins, then the origin that served this page.
  static Uri _defaultHostUri() {
    final fromQuery = Uri.base.queryParameters['host'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return Uri.parse(
        fromQuery.contains('://') ? fromQuery : 'http://$fromQuery',
      );
    }
    if (kIsWeb) {
      return Uri.base.port == defaultServerPort
          ? Uri.parse(Uri.base.origin)
          : Uri.parse('http://${Uri.base.host}:$defaultServerPort');
    }
    return Uri.parse('http://127.0.0.1:$defaultServerPort');
  }
}

class _TvView extends StatefulWidget {
  const _TvView({required this.joinUri, required this.initialBrightness});

  final Uri joinUri;
  final Brightness initialBrightness;

  @override
  State<_TvView> createState() => _TvViewState();
}

class _TvViewState extends State<_TvView> {
  late Brightness _brightness = widget.initialBrightness;

  /// Whether this runs as an app on a handheld, where the screen is rotated
  /// and the system bars are hidden while the TV view is open.
  bool get _isHandheldApp =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_isHandheldApp) {
      // The canvas is 16:9, so a phone in portrait would show a tiny strip.
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
  }

  @override
  void dispose() {
    if (_isHandheldApp) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      setState(() {
        _brightness = _brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      unawaited(context.read<SpectatorSessionCubit>().reconnect());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = QuizmoApp.buildTheme(_brightness);
    final scheme = theme.colorScheme;

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surface,
                        Color.alphaBlend(
                          scheme.primary.withValues(alpha: 0.16),
                          scheme.surface,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: MediaQuery(
                  // Device text scaling would break the fixed canvas.
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.noScaling),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: kTvCanvasWidth,
                      height: kTvCanvasHeight,
                      child:
                          BlocBuilder<
                            SpectatorSessionCubit,
                            SpectatorSessionState
                          >(
                            builder: (context, state) =>
                                TvScreen(state: state, joinUri: widget.joinUri),
                          ),
                    ),
                  ),
                ),
              ),
              if (Navigator.of(context).canPop())
                // SafeArea keeps the button clear of the status bar and
                // display cutouts, where it could not be tapped.
                Positioned.fill(
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: IconButton.filledTonal(
                          tooltip: 'Close TV view',
                          iconSize: 28,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- stage ---

/// The 1920×1080 design canvas of the TV screen for a given [state].
///
/// Pure function of its inputs (no networking), which keeps it testable.
class TvScreen extends StatelessWidget {
  /// Creates the canvas content.
  const TvScreen({required this.state, required this.joinUri, super.key});

  final SpectatorSessionState state;
  final Uri joinUri;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 40, 64, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          const SizedBox(height: 32),
          Expanded(
            child: game == null
                ? _ConnectingStage(state: state, joinUri: joinUri)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MainStage(
                          game: game,
                          state: state,
                          joinUri: joinUri,
                        ),
                      ),
                      const SizedBox(width: 40),
                      SizedBox(width: 620, child: _StandingsPanel(game: game)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SpectatorSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = state.game?.mode.label;

    return SizedBox(
      height: 72,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.bolt, size: 40, color: scheme.onPrimary),
          ),
          const SizedBox(width: 20),
          Text(
            'Quizmo',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          if (state.serverName case final name?) ...[
            const SizedBox(width: 20),
            Text(
              name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 28,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const Spacer(),
          if (mode != null) ...[
            _Pill(label: mode, color: scheme.secondaryContainer),
            const SizedBox(width: 16),
          ],
          _ConnectionPill(state: state),
          // Leave room for the close button of the dashboard preview.
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.state});

  final SpectatorSessionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = state.isConnected
        ? ('LIVE', Colors.green)
        : (
            state.reconnectAttempt == 0 ? 'CONNECTING' : 'RECONNECTING',
            scheme.tertiary,
          );
    return _Pill(
      label: label,
      color: color.withValues(alpha: 0.22),
      dotColor: color,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.dotColor});

  final String label;
  final Color color;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded surface that frames one area of the canvas.
class _TvPanel extends StatelessWidget {
  const _TvPanel({required this.child, this.padding = 48});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

// ----------------------------------------------------------- connecting ---

class _ConnectingStage extends StatelessWidget {
  const _ConnectingStage({required this.state, required this.joinUri});

  final SpectatorSessionState state;
  final Uri joinUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFailed = state.reconnectAttempt > 0 || state.error != null;

    return _TvPanel(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                strokeWidth: 8,
                color: hasFailed ? scheme.tertiary : scheme.primary,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              hasFailed
                  ? 'Host not reachable — retrying…'
                  : 'Connecting to the quiz…',
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 56,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              joinUri.authority,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 40,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasFailed) ...[
              const SizedBox(height: 20),
              Text(
                'Make sure the TV and the quizmaster are on the same network '
                'and the host server is running.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 28,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ main stage ---

class _MainStage extends StatelessWidget {
  const _MainStage({
    required this.game,
    required this.state,
    required this.joinUri,
  });

  final GameState game;
  final SpectatorSessionState state;
  final Uri joinUri;

  @override
  Widget build(BuildContext context) {
    final question = game.round.question;
    final jeopardy = game.jeopardy;
    return _TvPanel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: switch ((question, jeopardy)) {
          (final Question current, _) => _QuestionStage(
            key: ValueKey(current.id),
            game: game,
            question: current,
            state: state,
          ),
          (null, final JeopardyState board)
              when board.pendingDailyDoubleId != null =>
            _DailyDoubleStage(
              key: ValueKey('daily-${board.pendingDailyDoubleId}'),
              game: game,
              jeopardy: board,
            ),
          (null, final JeopardyState board) => _JeopardyBoardStage(
            key: const ValueKey('board'),
            game: game,
            jeopardy: board,
            joinUri: joinUri,
          ),
          (null, null) => _LobbyStage(
            key: const ValueKey('lobby'),
            game: game,
            joinUri: joinUri,
          ),
        },
      ),
    );
  }
}

// --------------------------------------------------------------- jeopardy ---

/// The board between two questions: whose turn it is and what is left.
class _JeopardyBoardStage extends StatelessWidget {
  const _JeopardyBoardStage({
    required this.game,
    required this.jeopardy,
    required this.joinUri,
    super.key,
  });

  final GameState game;
  final JeopardyState jeopardy;
  final Uri joinUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picker = game.teams[jeopardy.currentTeamId];
    final remaining = jeopardy.board.questionIds
        .where((id) => !game.completedQuestionIds.contains(id))
        .length;
    final isOpening = game.completedQuestionIds.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 32,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (remaining == 0)
              Text(
                'Board cleared — check the standings!',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                ),
              )
            else if (picker != null)
              _Pill(
                label: '${picker.name} picks the next question',
                color: Color(picker.colorValue).withValues(alpha: 0.35),
                dotColor: Color(picker.colorValue),
              ),
            if (isOpening)
              Text(
                'Join: ${joinUri.authority}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: JeopardyBoardView(
            board: jeopardy.board,
            completedQuestionIds: game.completedQuestionIds,
            style: JeopardyBoardStyle.tv,
          ),
        ),
      ],
    );
  }
}

class _DailyDoubleStage extends StatelessWidget {
  const _DailyDoubleStage({
    required this.game,
    required this.jeopardy,
    super.key,
  });

  final GameState game;
  final JeopardyState jeopardy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = jeopardy.pendingDailyDoubleId;
    final category = id == null ? null : jeopardy.board.categoryNameOf(id);
    final picker = game.teams[jeopardy.currentTeamId];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 200, color: scheme.tertiary),
          const SizedBox(height: 16),
          Text(
            'DAILY DOUBLE',
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 120,
              fontWeight: FontWeight.w900,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(height: 24),
          if (category != null)
            _Pill(label: category, color: scheme.tertiaryContainer),
          const SizedBox(height: 32),
          Text(
            '${picker?.name ?? 'The picking team'}, place your wager!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyStage extends StatelessWidget {
  const _LobbyStage({required this.game, required this.joinUri, super.key});

  final GameState game;
  final Uri joinUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final online = game.connectedPlayers;
    final hasPlayed = game.scores.history.isNotEmpty;
    const maxChips = 14;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          hasPlayed ? 'Next question coming up…' : 'Get ready to play!',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: 64,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Always dark-on-white, whatever the theme: scanners need contrast.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.all(20),
              child: QrImageView(
                data: joinUri.toString(),
                size: 300,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                semanticsLabel: 'QR code to join at $joinUri',
              ),
            ),
            const SizedBox(width: 56),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan to join with your phone',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'or open',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    joinUri.authority,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        Text(
          online.isEmpty
              ? 'Waiting for the first player…'
              : '${online.length} ${online.length == 1 ? 'player' : 'players'} '
                    'online',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final player in online.take(maxChips))
              _Pill(label: player.name, color: scheme.primaryContainer),
            if (online.length > maxChips)
              _Pill(
                label: '+${online.length - maxChips}',
                color: scheme.surfaceContainerHighest,
              ),
          ],
        ),
      ],
    );
  }
}

class _QuestionStage extends StatelessWidget {
  const _QuestionStage({
    required this.game,
    required this.question,
    required this.state,
    super.key,
  });

  final GameState game;
  final Question question;
  final SpectatorSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final round = game.round;
    final isRevealed = round.status == RoundStatus.revealed;
    // Local copy: public fields are not promoted by the switch below.
    final current = question;
    final jeopardy = game.jeopardy;
    final boardCategory = jeopardy?.board.categoryNameOf(question.id);
    final picker = game.teams[jeopardy?.currentTeamId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  if (boardCategory ?? question.category case final category?)
                    _Pill(label: category, color: scheme.tertiaryContainer),
                  if (jeopardy != null && jeopardy.hasActiveQuestion) ...[
                    _Pill(
                      label: '${jeopardy.activePoints} pts',
                      color: scheme.primaryContainer,
                    ),
                    if (jeopardy.activeIsDailyDouble)
                      _Pill(
                        label: 'DAILY DOUBLE',
                        color: scheme.tertiary.withValues(alpha: 0.4),
                        dotColor: scheme.tertiary,
                      ),
                    if (picker != null && !isRevealed)
                      _Pill(
                        label: jeopardy.isStealRound
                            ? 'STEAL: everyone but ${picker.name}'
                            : '${picker.name} answers',
                        color: Color(picker.colorValue).withValues(alpha: 0.35),
                        dotColor: Color(picker.colorValue),
                      ),
                  ] else
                    _Pill(
                      label: question.kindLabel,
                      color: scheme.secondaryContainer,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _RoundStatusPill(status: round.status),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          question.prompt,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: _promptSize(question.prompt.length),
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 28),
        // The slot is always reserved so the answers do not jump when the
        // clock disappears after the reveal.
        SizedBox(
          height: 56,
          child: round.status == RoundStatus.acceptingAnswers
              ? _CountdownBar(state: state, limit: question.timeLimit)
              : null,
        ),
        const SizedBox(height: 28),
        Expanded(
          // Exhaustive over the sealed hierarchy: a new question type does not
          // compile until the TV knows how to render it.
          child: switch (current) {
            MultipleChoiceQuestion() => _ChoiceBoard(
              question: current,
              game: game,
            ),
            BuzzerQuestion() => _BuzzerBoard(question: current, game: game),
          },
        ),
        if (isRevealed) _AwardsRow(game: game, questionId: question.id),
      ],
    );
  }

  /// Picks the largest type size that still lets the prompt fit.
  static double _promptSize(int length) => switch (length) {
    <= 60 => 76,
    <= 120 => 64,
    <= 200 => 52,
    _ => 44,
  };
}

class _RoundStatusPill extends StatelessWidget {
  const _RoundStatusPill({required this.status});

  final RoundStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      RoundStatus.idle => const SizedBox.shrink(),
      RoundStatus.acceptingAnswers => _Pill(
        label: 'OPEN',
        color: Colors.green.withValues(alpha: 0.25),
        dotColor: Colors.green,
      ),
      RoundStatus.locked => _Pill(
        label: 'LOCKED',
        color: scheme.tertiary.withValues(alpha: 0.25),
        dotColor: scheme.tertiary,
      ),
      RoundStatus.revealed => _Pill(
        label: 'SOLUTION',
        color: scheme.primary.withValues(alpha: 0.25),
        dotColor: scheme.primary,
      ),
    };
  }
}

// ------------------------------------------------------------- countdown ---

class _CountdownBar extends StatefulWidget {
  const _CountdownBar({required this.state, required this.limit});

  final SpectatorSessionState state;
  final Duration limit;

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = widget.state.remainingTime(DateTime.now());
    if (remaining == null) return const SizedBox.shrink();

    final fraction = widget.limit.inMicroseconds == 0
        ? 0.0
        : (remaining.inMicroseconds / widget.limit.inMicroseconds).clamp(
            0.0,
            1.0,
          );
    final isUrgent = remaining <= const Duration(seconds: 5);
    final color = isUrgent ? scheme.error : scheme.primary;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 20,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 28),
        SizedBox(
          width: 130,
          child: Text(
            remaining == Duration.zero
                ? "Time's up"
                : '${(remaining.inMilliseconds / 1000).ceil()} s',
            textAlign: TextAlign.end,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: remaining == Duration.zero ? 30 : 52,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- multiple choice ---

class _ChoiceBoard extends StatelessWidget {
  const _ChoiceBoard({required this.question, required this.game});

  final MultipleChoiceQuestion question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = game.round;
    final isRevealed = round.status == RoundStatus.revealed;
    final options = question.options;

    final tally = <String, int>{};
    for (final answer in round.answers.values) {
      tally[answer.optionId] = (tally[answer.optionId] ?? 0) + 1;
    }

    Widget tile(int index) => _ChoiceTile(
      letter: String.fromCharCode(0x41 + index),
      label: options[index].label,
      // Per-option counts would let late players copy the crowd, so they are
      // only shown once the solution is public.
      votes: isRevealed ? tally[options[index].id] ?? 0 : null,
      verdict: !isRevealed
          ? _ChoiceVerdict.neutral
          : question.isCorrect(options[index].id)
          ? _ChoiceVerdict.correct
          : _ChoiceVerdict.wrong,
    );

    final rowCount = (options.length + 1) ~/ 2;
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < rowCount; row++) ...[
                if (row > 0) const SizedBox(height: 24),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: tile(row * 2)),
                      const SizedBox(width: 24),
                      Expanded(
                        child: row * 2 + 1 < options.length
                            ? tile(row * 2 + 1)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!isRevealed) ...[
          const SizedBox(height: 24),
          Text(
            '${round.answers.length} of ${game.connectedPlayers.length} '
            'answered',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

enum _ChoiceVerdict { neutral, correct, wrong }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.letter,
    required this.label,
    required this.verdict,
    this.votes,
  });

  final String letter;
  final String label;
  final _ChoiceVerdict verdict;
  final int? votes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, border, badge) = switch (verdict) {
      _ChoiceVerdict.neutral => (
        scheme.surfaceContainerHighest,
        scheme.outlineVariant,
        scheme.primary,
      ),
      _ChoiceVerdict.correct => (
        Colors.green.withValues(alpha: 0.30),
        Colors.green,
        Colors.green,
      ),
      _ChoiceVerdict.wrong => (
        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        scheme.outlineVariant.withValues(alpha: 0.4),
        scheme.outline,
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: border,
          width: verdict == _ChoiceVerdict.correct ? 6 : 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
            child: verdict == _ChoiceVerdict.correct
                ? const Icon(Icons.check, size: 56, color: Colors.white)
                : Text(
                    letter,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: verdict == _ChoiceVerdict.wrong
                    ? scheme.onSurface.withValues(alpha: 0.55)
                    : scheme.onSurface,
              ),
            ),
          ),
          if (votes case final count?)
            Text(
              '×$count',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- buzzer ---

class _BuzzerBoard extends StatelessWidget {
  const _BuzzerBoard({required this.question, required this.game});

  final BuzzerQuestion question;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final round = game.round;
    final isRevealed = round.status == RoundStatus.revealed;
    final activeName = game.activePlayer?.name;

    if (round.buzzerQueue.isEmpty && !isRevealed) {
      return const _PulsingBuzzerHint();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (round.status == RoundStatus.locked && activeName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              '$activeName is answering…',
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 60,
                fontWeight: FontWeight.w800,
                color: scheme.tertiary,
              ),
            ),
          ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1060,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < round.buzzerQueue.length && index < 5;
                    index++
                  )
                    _BuzzRow(
                      index: index,
                      name:
                          game
                              .players[round.buzzerQueue[index].playerId]
                              ?.name ??
                          'Player',
                      gap: round.gapToFastest(round.buzzerQueue[index]),
                      isActive:
                          round.activePlayerId ==
                              round.buzzerQueue[index].playerId &&
                          !isRevealed,
                      hasMissed: round.lockedOutPlayerIds.contains(
                        round.buzzerQueue[index].playerId,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (isRevealed && question.expectedAnswer != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.green, width: 6),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 64, color: Colors.green),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    question.expectedAnswer!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BuzzRow extends StatelessWidget {
  const _BuzzRow({
    required this.index,
    required this.name,
    required this.gap,
    required this.isActive,
    required this.hasMissed,
  });

  final int index;
  final String name;
  final Duration gap;
  final bool isActive;
  final bool hasMissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '${index + 1}.',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                decoration: hasMissed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(
            index == 0
                ? 'FASTEST'
                : '+${formatMicrosAsMillis(gap.inMicroseconds)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: index == 0 ? Colors.green : scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingBuzzerHint extends StatefulWidget {
  const _PulsingBuzzerHint();

  @override
  State<_PulsingBuzzerHint> createState() => _PulsingBuzzerHintState();
}

class _PulsingBuzzerHintState extends State<_PulsingBuzzerHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: Icon(Icons.bolt, size: 200, color: scheme.tertiary),
          ),
          const SizedBox(height: 16),
          Text(
            'Buzzers are armed!',
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 64,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Be the first to hit your buzzer.',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 34,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- awards ---

/// Points booked for the revealed question, so the room sees who scored.
class _AwardsRow extends StatelessWidget {
  const _AwardsRow({required this.game, required this.questionId});

  final GameState game;
  final String questionId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final byPlayer = <String, int>{};
    for (final event in game.scores.history) {
      if (event.questionId != questionId) continue;
      byPlayer[event.playerId] = (byPlayer[event.playerId] ?? 0) + event.points;
    }
    final awards = byPlayer.entries.where((entry) => entry.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (awards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          for (final award in awards.take(6))
            _Pill(
              label:
                  '${award.value > 0 ? '+' : ''}${award.value}  '
                  '${game.players[award.key]?.name ?? 'Player'}',
              color: award.value > 0
                  ? Colors.green.withValues(alpha: 0.28)
                  : scheme.error.withValues(alpha: 0.28),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- standings ---

class _StandingsPanel extends StatelessWidget {
  const _StandingsPanel({required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final standings = buildTvStandings(game);

    return _TvPanel(
      padding: 36,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.leaderboard, size: 44, color: scheme.primary),
              const SizedBox(width: 16),
              Text(
                'Standings',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: standings.entries.isEmpty
                ? Center(
                    child: Text(
                      game.mode is TeamMode ? 'No teams yet' : 'No players yet',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 32,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 548,
                      child: Column(
                        children: [
                          for (final entry in standings.entries)
                            _StandingRow(entry: entry),
                          if (standings.hiddenCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '+${standings.hiddenCount} more',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 28,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.entry});

  final TvStanding entry;

  static const _medals = [
    Color(0xFFFFC107), // gold
    Color(0xFFB0BEC5), // silver
    Color(0xFFCD7F32), // bronze
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final medal = entry.rank <= 3 && entry.points > 0
        ? _medals[entry.rank - 1]
        : null;
    final accent = entry.colorValue == null ? null : Color(entry.colorValue!);

    return Opacity(
      opacity: entry.isOnline ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: accent == null
              ? null
              : Border(left: BorderSide(color: accent, width: 10)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal ?? Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${entry.rank}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: medal == null ? scheme.onSurfaceVariant : Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (entry.subtitle case final subtitle?)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entry.points}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
