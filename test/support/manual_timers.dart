import 'dart:async';

/// A clock and timers that only move when a test advances them.
final class ManualTimers {
  int nowMicros = 0;
  final List<_ManualTimer> _timers = [];

  Timer create(Duration duration, void Function() callback) {
    final timer = _ManualTimer(nowMicros + duration.inMicroseconds, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    nowMicros += duration.inMicroseconds;
    for (final timer in [..._timers]) {
      if (timer.isActive && timer.dueMicros <= nowMicros) timer.fire();
    }
    _timers.removeWhere((timer) => !timer.isActive);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.dueMicros, this._callback);

  final int dueMicros;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}
