/// Tells a player clearly that something is expected of them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../l10n/app_localizations.dart';
import 'player_session_cubit.dart';

/// What the host waits for on this device.
enum PlayerTurn {
  /// An answer to the question on stage.
  answer,

  /// The buzzer is free.
  buzz,

  /// The stake of the own team in a poker question.
  stake,
}

/// What [state] expects of its player now; `null` when nothing is open: not
/// joined, already answered or buzzed, out, or only the host acts.
PlayerTurn? pendingTurn(PlayerSessionState state) {
  final game = state.game;
  final question = state.question;
  if (!state.isConnected || game == null || question == null) return null;
  if (game.showsSlide || game.isFinished || game.recoveryPaused) return null;
  final round = game.round;
  final team = state.me?.teamId;
  if (game.poker case final poker?) {
    if (poker.betting) {
      // The category phase only offers jokers, which are optional.
      return !poker.questionHidden &&
              team != null &&
              (poker.chips[team] ?? 0) > 0 &&
              !poker.wagers.containsKey(team) &&
              round.status.acceptsInput
          ? PlayerTurn.stake
          : null;
    }
  }
  if (!round.status.acceptsInput || round.verbal) return null;
  if (!state.mayAnswerQuestion) return null;
  if (question is BuzzerQuestion) {
    return state.hasBuzzed ||
            round.activePlayerId != null ||
            round.lockedOutPlayerIds.contains(state.playerId)
        ? null
        : PlayerTurn.buzz;
  }
  final answered =
      state.lastSubmittedOptionId != null ||
      state.answers?.own != null ||
      state.answers?.valid != null;
  return state.mayEditAnswer && state.mayAnswerPoker && !answered
      ? PlayerTurn.answer
      : null;
}

/// Shows "Your turn!" for a moment and vibrates once whenever [state] starts
/// to expect something new of its player. The same action never signals
/// twice, also not after a reconnect or when the page is built again.
class YourTurnSignal extends StatefulWidget {
  const YourTurnSignal({required this.state, required this.child, super.key});

  final PlayerSessionState state;
  final Widget child;

  /// How long the notice stays.
  static const duration = Duration(milliseconds: 1600);

  /// Actions that already signalled in this app run.
  static final _signalled = <String>{};

  /// Forgets every signalled action (tests).
  @visibleForTesting
  static void reset() => _signalled.clear();

  @override
  State<YourTurnSignal> createState() => _YourTurnSignalState();
}

class _YourTurnSignalState extends State<YourTurnSignal> {
  PlayerTurn? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(YourTurnSignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  void _check() {
    final turn = pendingTurn(widget.state);
    if (turn == null) {
      if (_shown != null) _dismiss();
      return;
    }
    final round = widget.state.game!.round;
    final key = [
      widget.state.playerId,
      round.question?.id,
      round.startedAtHostMicros,
      turn.name,
    ].join('/');
    if (!YourTurnSignal._signalled.add(key)) return;
    _shown = turn;
    _hide?.cancel();
    _hide = Timer(YourTurnSignal.duration, () {
      if (mounted) _dismiss();
    });
    // Browsers without the vibration API (iOS Safari) ignore it.
    unawaited(HapticFeedback.vibrate().catchError((Object _) {}));
  }

  void _dismiss() => setState(() => _shown = null);

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: shown == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: shown == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: Material(
                        key: const ValueKey('your-turn'),
                        color: scheme.error,
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.tr('Du bist dran!'),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: scheme.onError,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              Text(switch (shown) {
                                PlayerTurn.answer => context.tr(
                                  'Gib jetzt deine Antwort ein.',
                                ),
                                PlayerTurn.buzz => context.tr(
                                  'Der Buzzer ist frei.',
                                ),
                                PlayerTurn.stake => context.tr(
                                  'Setz jetzt deine Chips.',
                                ),
                              }, style: TextStyle(color: scheme.onError)),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
