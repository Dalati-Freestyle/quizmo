/// The latency critical buzzer control.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Visual and functional state of a [BuzzerButton].
enum BuzzerMode {
  /// Armed and waiting for a press.
  ready,

  /// This client already buzzed and is waiting for the host.
  submitted,

  /// This client owns the floor.
  won,

  /// Somebody else owns the floor, or the round is closed.
  locked,
}

/// A large press target bound to [Listener.onPointerDown].
///
/// ## Why `onPointerDown` and not `onTap`
///
/// `GestureDetector.onTap` only fires once the gesture arena has decided that
/// the pointer sequence is a tap, which costs at least the pointer-up event and
/// can cost far more when an ancestor scrollable competes for the gesture. In a
/// buzzer race those tens of milliseconds are the whole game, so the press is
/// taken from the raw pointer event and timestamped immediately
/// (architecture: "Buzzer Responsiveness").
class BuzzerButton extends StatefulWidget {
  /// Creates a buzzer.
  const BuzzerButton({
    required this.onPressed,
    this.mode = BuzzerMode.ready,
    this.label = 'BUZZ',
    this.hint,
    super.key,
  });

  /// Invoked synchronously on pointer down while [mode] is [BuzzerMode.ready].
  final VoidCallback onPressed;

  /// Current visual and functional state.
  final BuzzerMode mode;

  /// Text rendered in the centre.
  final String label;

  /// Optional secondary line below [label].
  final String? hint;

  @override
  State<BuzzerButton> createState() => _BuzzerButtonState();
}

class _BuzzerButtonState extends State<BuzzerButton> {
  bool _isDown = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.mode != BuzzerMode.ready) return;
    setState(() => _isDown = true);
    // Fire before any awaits or animations so nothing delays the timestamp.
    widget.onPressed();
    unawaited(HapticFeedback.heavyImpact());
  }

  void _release([PointerEvent? _]) {
    if (!_isDown) return;
    setState(() => _isDown = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (widget.mode) {
      BuzzerMode.ready => (scheme.error, scheme.onError, Icons.touch_app),
      BuzzerMode.submitted => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.hourglass_top,
      ),
      BuzzerMode.won => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.emoji_events,
      ),
      BuzzerMode.locked => (
        scheme.surfaceContainerHighest,
        scheme.outline,
        Icons.lock_outline,
      ),
    };

    return Semantics(
      button: true,
      enabled: widget.mode == BuzzerMode.ready,
      label: widget.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: AnimatedScale(
          scale: _isDown ? 0.94 : 1,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 180),
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              boxShadow: widget.mode == BuzzerMode.ready && !_isDown
                  ? [
                      BoxShadow(
                        color: background.withValues(alpha: 0.45),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: foreground),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  if (widget.hint case final hint?) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


