/// How audio and video behave on the different devices.
library;

import 'package:flutter/widgets.dart';

import '../../core/models/models.dart';

/// What a view may do with its audio and video.
enum MediaPlayback {
  /// Starts by itself and follows every command of the host (TV).
  automatic,

  /// Starts only when somebody presses play on this very device.
  onDemand,

  /// Stands still now, but may be started on this device.
  stopped,

  /// Paused by the host: stands still and cannot be started here.
  paused;

  /// Media on the TV; [silent] while something else plays there.
  static MediaPlayback onTv(GameState game, {bool silent = false}) =>
      game.tvMediaPaused
      ? MediaPlayback.paused
      : silent
      ? MediaPlayback.stopped
      : MediaPlayback.automatic;

  /// Media on a player device or on the device of the host, which never start
  /// anything by themselves; [stopped] when newer media took over.
  static MediaPlayback onDevice(GameState? game, {bool stopped = false}) =>
      game?.tvMediaPaused ?? false
      ? MediaPlayback.paused
      : stopped
      ? MediaPlayback.stopped
      : MediaPlayback.onDemand;
}

/// Media below it are only a picture of what another device shows: they never
/// play, make no sound and offer no controls.
class StillMedia extends InheritedWidget {
  const StillMedia({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StillMedia>() != null;

  @override
  bool updateShouldNotify(StillMedia oldWidget) => false;
}

/// Learns which media below it could not start because the browser blocks
/// playback with sound until somebody presses a key.
class MediaBlockReporter extends InheritedWidget {
  const MediaBlockReporter({
    required this.onChanged,
    required super.child,
    super.key,
  });

  /// Called with the blocked (or released) player.
  final void Function(Object source, bool blocked) onChanged;

  static MediaBlockReporter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MediaBlockReporter>();

  @override
  bool updateShouldNotify(MediaBlockReporter oldWidget) => false;
}
