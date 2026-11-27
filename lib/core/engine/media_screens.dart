import 'dart:async';

/// The connected TVs that could not start audio or video by themselves,
/// because their browser wants a key press first. Not part of the game.
final class MediaScreens {
  final Set<String> _blocked = {};
  final StreamController<bool> _changes = StreamController.broadcast();

  /// Whether at least one TV waits for a confirmation.
  bool get anyBlocked => _blocked.isNotEmpty;

  /// Emits [anyBlocked] with every change.
  Stream<bool> get changes => _changes.stream;

  void report(String screenId, {required bool blocked}) {
    final changed = blocked
        ? _blocked.add(screenId)
        : _blocked.remove(screenId);
    if (changed && !_changes.isClosed) _changes.add(anyBlocked);
  }

  void close() => unawaited(_changes.close());
}
