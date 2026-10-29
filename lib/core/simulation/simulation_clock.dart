import 'dart:async';

final class SimulationClock {
  int nowMicros = 0;
  int _sequence = 0;
  final List<_ScheduledTimer> _timers = [];

  Timer schedule(Duration delay, void Function() callback) {
    if (delay.isNegative) throw ArgumentError.value(delay, 'delay');
    final timer = _ScheduledTimer(
      nowMicros + delay.inMicroseconds,
      _sequence++,
      callback,
    );
    _timers.add(timer);
    return timer;
  }

  Future<void> advance(Duration duration) async {
    if (duration.isNegative) throw ArgumentError.value(duration, 'duration');
    final target = nowMicros + duration.inMicroseconds;
    await Future<void>.delayed(Duration.zero);
    while (true) {
      _timers.removeWhere((timer) => !timer.isActive);
      _timers.sort((a, b) {
        final time = a.due.compareTo(b.due);
        return time == 0 ? a.sequence.compareTo(b.sequence) : time;
      });
      if (_timers.isEmpty || _timers.first.due > target) break;
      final timer = _timers.removeAt(0);
      nowMicros = timer.due;
      timer.fire();
      // Drain the BLoC's asynchronous event queue before advancing host time.
      await Future<void>.delayed(Duration.zero);
    }
    nowMicros = target;
  }

  void cancelAll() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  int get pendingCount => _timers.where((timer) => timer.isActive).length;
}

final class _ScheduledTimer implements Timer {
  _ScheduledTimer(this.due, this.sequence, this.callback);
  final int due;
  final int sequence;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
}
