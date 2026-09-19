/// Unit tests for the NTP style clock synchronisation math.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/sync/clock_sync.dart';

void main() {
  group('ClockSample', () {
    test('computes the round trip time', () {
      const sample = ClockSample(
        clientSentAtMicros: 1000,
        hostTimeMicros: 5000,
        clientReceivedAtMicros: 1400,
      );

      expect(sample.roundTripMicros, 400);
      expect(sample.oneWayLatency.inMicroseconds, 200);
    });

    test('reports a zero offset for a perfectly aligned clock', () {
      // The host stamped exactly at the midpoint of the round trip.
      const sample = ClockSample(
        clientSentAtMicros: 1000,
        hostTimeMicros: 1200,
        clientReceivedAtMicros: 1400,
      );

      expect(sample.clockOffsetMicros, 0);
    });

    test('reports a positive offset when the client clock runs ahead', () {
      const sample = ClockSample(
        clientSentAtMicros: 6000,
        hostTimeMicros: 1200,
        clientReceivedAtMicros: 6400,
      );

      expect(sample.clockOffsetMicros, 5000);
    });

    test('reports a negative offset when the client clock lags', () {
      const sample = ClockSample(
        clientSentAtMicros: 1000,
        hostTimeMicros: 4200,
        clientReceivedAtMicros: 1400,
      );

      expect(sample.clockOffsetMicros, -3000);
    });
  });

  group('ClockSyncEstimator', () {
    test('starts unsynchronised and neutral', () {
      final estimator = ClockSyncEstimator();

      expect(estimator.isSynced, isFalse);
      expect(estimator.clockOffsetMicros, 0);
      expect(estimator.toHostTimestamp(1234), 1234);
    });

    test('prefers the probe with the lowest round trip time', () {
      final estimator = ClockSyncEstimator();

      // A slow, badly skewed probe.
      estimator.add(
        const ClockSample(
          clientSentAtMicros: 0,
          hostTimeMicros: 40000,
          clientReceivedAtMicros: 200000,
        ),
      );
      // A fast probe: the client is 1 ms ahead of the host.
      estimator.add(
        const ClockSample(
          clientSentAtMicros: 1000000,
          hostTimeMicros: 999200,
          clientReceivedAtMicros: 1000400,
        ),
      );

      expect(estimator.isSynced, isTrue);
      expect(estimator.roundTripMicros, 400);
      expect(estimator.clockOffsetMicros, 1000);
    });

    test('projects local timestamps onto the host timeline', () {
      final estimator = ClockSyncEstimator();
      estimator.add(
        const ClockSample(
          clientSentAtMicros: 1000000,
          hostTimeMicros: 999200,
          clientReceivedAtMicros: 1000400,
        ),
      );

      // Architecture Rule 3: hostTimestamp = clientTimestamp - clockOffset.
      expect(estimator.toHostTimestamp(1500000), 1499000);
    });

    test('keeps only the configured window of probes', () {
      final estimator = ClockSyncEstimator(windowSize: 2);
      for (var index = 0; index < 5; index++) {
        estimator.add(
          ClockSample(
            clientSentAtMicros: index * 1000,
            hostTimeMicros: index * 1000 + 500,
            clientReceivedAtMicros: index * 1000 + 1000,
          ),
        );
      }

      expect(estimator.samples, hasLength(2));
    });

    test('exposes the spread between the retained offsets as jitter', () {
      final estimator = ClockSyncEstimator();
      estimator.add(
        const ClockSample(
          clientSentAtMicros: 0,
          hostTimeMicros: 0,
          clientReceivedAtMicros: 400,
        ),
      );
      estimator.add(
        const ClockSample(
          clientSentAtMicros: 0,
          hostTimeMicros: 300,
          clientReceivedAtMicros: 400,
        ),
      );

      expect(estimator.jitterMicros, 300);
    });

    test('reset drops every probe', () {
      final estimator = ClockSyncEstimator()
        ..add(
          const ClockSample(
            clientSentAtMicros: 0,
            hostTimeMicros: 100,
            clientReceivedAtMicros: 400,
          ),
        )
        ..reset();

      expect(estimator.isSynced, isFalse);
      expect(estimator.samples, isEmpty);
    });
  });
}

