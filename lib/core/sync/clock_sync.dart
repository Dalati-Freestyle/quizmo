/// NTP style clock synchronisation between a client and the embedded host.
///
/// ## Why this exists
///
/// A buzzer race is decided in single digit milliseconds. Ordering the presses
/// by the moment their packet reaches the host would simply crown whoever sits
/// closest to the access point. Instead every client measures how far its own
/// clock runs ahead of the host clock and reports that offset with each press,
/// so the host can project all presses onto one common timeline.
///
/// ## Sign convention
///
/// `clockOffset = clientClock - hostClock`
///
/// A **positive** offset means the client clock is ahead of the host clock,
/// hence `hostTimestamp = clientTimestamp - clockOffset` (architecture Rule 3).
library;

import 'package:equatable/equatable.dart';

import '../models/json.dart';
import 'clock.dart';

/// A single completed round trip against the host clock.
///
/// The three timestamps correspond to Cristian's algorithm:
///
/// ```text
/// t0 ── client sends ──────────────►
///                                    t1 host stamps the request
/// t2 ◄──────────── client receives ──
/// ```
final class ClockSample extends Equatable {
  /// Creates a sample from the three measured instants.
  const ClockSample({
    required this.clientSentAtMicros,
    required this.hostTimeMicros,
    required this.clientReceivedAtMicros,
  });

  /// Restores a sample from [json] plus the locally measured arrival time.
  factory ClockSample.fromResponse(
    JsonMap json, {
    required int clientReceivedAtMicros,
  }) => ClockSample(
    clientSentAtMicros: json.readInt('clientSentAtMicros'),
    hostTimeMicros: json.readInt('hostTimeMicros'),
    clientReceivedAtMicros: clientReceivedAtMicros,
  );

  /// `t0` — client clock when the probe was sent.
  final int clientSentAtMicros;

  /// `t1` — host clock when the probe was handled.
  final int hostTimeMicros;

  /// `t2` — client clock when the response arrived.
  final int clientReceivedAtMicros;

  /// Full round trip time of this probe.
  int get roundTripMicros => clientReceivedAtMicros - clientSentAtMicros;

  /// Estimated one way latency, assuming a symmetric path.
  Duration get oneWayLatency => Duration(microseconds: roundTripMicros ~/ 2);

  /// How far the client clock runs ahead of the host clock.
  ///
  /// The client midpoint `(t0 + t2) / 2` approximates the client clock at the
  /// instant the host stamped `t1`.
  int get clockOffsetMicros =>
      ((clientSentAtMicros + clientReceivedAtMicros) ~/ 2) - hostTimeMicros;

  @override
  List<Object?> get props => [
    clientSentAtMicros,
    hostTimeMicros,
    clientReceivedAtMicros,
  ];

  @override
  String toString() =>
      'ClockSample(rtt: ${formatMicrosAsMillis(roundTripMicros)}, '
      'offset: ${formatSignedMicrosAsMillis(clockOffsetMicros)})';
}

/// Keeps a sliding window of [ClockSample]s and exposes the best estimate.
///
/// Like NTP, the sample with the **lowest round trip time** wins: a fast probe
/// had the least opportunity to be distorted by queueing delay, so its
/// symmetric path assumption is the most trustworthy one.
final class ClockSyncEstimator {
  /// Creates an estimator that keeps the last [windowSize] probes.
  ClockSyncEstimator({this.windowSize = 8, NowMicros now = systemNowMicros})
    : _now = now;

  /// Number of probes retained before the oldest one is dropped.
  final int windowSize;

  final NowMicros _now;
  final List<ClockSample> _samples = <ClockSample>[];
  ClockSample? _best;

  /// Adds [sample] and recomputes the current best estimate.
  void add(ClockSample sample) {
    _samples.add(sample);
    while (_samples.length > windowSize) {
      _samples.removeAt(0);
    }
    _best = _samples.reduce(
      (a, b) => b.roundTripMicros < a.roundTripMicros ? b : a,
    );
  }

  /// Whether at least one probe completed.
  bool get isSynced => _best != null;

  /// The probe currently used for the estimate.
  ClockSample? get bestSample => _best;

  /// All retained probes, oldest first.
  List<ClockSample> get samples => List.unmodifiable(_samples);

  /// Current `client - host` offset; zero while unsynchronised.
  int get clockOffsetMicros => _best?.clockOffsetMicros ?? 0;

  /// Round trip time of the best probe; zero while unsynchronised.
  int get roundTripMicros => _best?.roundTripMicros ?? 0;

  /// Estimated one way latency of the best probe.
  Duration get latency => Duration(microseconds: roundTripMicros ~/ 2);

  /// Spread between the best and the worst retained offset.
  ///
  /// A large jitter is a good hint for the UI that the estimate is shaky.
  int get jitterMicros {
    if (_samples.length < 2) return 0;
    final offsets = _samples
        .map((sample) => sample.clockOffsetMicros)
        .toList(growable: false)
      ..sort();
    return offsets.last - offsets.first;
  }

  /// Projects the local timestamp [localMicros] onto the host timeline.
  int toHostTimestamp(int localMicros) => localMicros - clockOffsetMicros;

  /// The current instant, expressed on the host timeline.
  int get hostNowMicros => toHostTimestamp(_now());

  /// Drops every retained probe.
  void reset() {
    _samples.clear();
    _best = null;
  }
}

