import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/engine/tech_check.dart';
import 'package:quizmo/core/models/models.dart';

const _question = TrueFalseQuestion(id: 'q', prompt: 'Q', correctAnswer: true);

TechCheckInput _input({
  bool running = true,
  bool internet = false,
  HealthProbe health = const HealthAnswered(
    address: '192.168.0.2',
    elapsed: Duration(milliseconds: 12),
  ),
  List<Player> players = const [],
  List<TechCheckConnection> connections = const [],
  List<Question> questions = const [_question],
  bool tvRequired = true,
  bool mediaRequired = true,
  Set<String>? deviceTest,
}) => TechCheckInput(
  deviceTestConfirmed: deviceTest,
  serverRunning: running,
  internet: internet,
  health: health,
  players: players,
  connections: connections,
  questions: questions,
  tvRequired: tvRequired,
  mediaRequired: mediaRequired,
);

TechCheckResult _result(TechCheckInput input, TechCheckId id) =>
    evaluateTechCheck(input).firstWhere((result) => result.id == id);

TechCheckConnection _player(String id, {int silentSeconds = 1}) =>
    TechCheckConnection(
      kind: TechCheckConnectionKind.player,
      playerId: id,
      silentFor: Duration(seconds: silentSeconds),
    );

const _tv = TechCheckConnection(
  kind: TechCheckConnectionKind.spectator,
  silentFor: Duration(seconds: 2),
);

void main() {
  group('host server', () {
    test('a stopped server fails', () {
      expect(
        _result(_input(running: false), TechCheckId.hostServer).status,
        TechCheckStatus.fail,
      );
    });

    test('an answered health request passes', () {
      expect(
        _result(_input(), TechCheckId.hostServer).status,
        TechCheckStatus.pass,
      );
    });

    test('unreachable and timed out health requests fail with a next step', () {
      for (final timedOut in [true, false]) {
        final result = _result(
          _input(health: HealthFailed(timedOut: timedOut)),
          TechCheckId.hostServer,
        );
        expect(result.status, TechCheckStatus.fail);
        expect(result.nextStep, isNotEmpty);
      }
    });

    test('a probe that did not run is not a success', () {
      expect(
        _result(
          _input(health: const HealthNotRun()),
          TechCheckId.hostServer,
        ).status,
        TechCheckStatus.notCheckable,
      );
    });
  });

  group('reachability', () {
    test('a local health check alone never claims external reachability', () {
      for (final internet in [false, true]) {
        expect(
          _result(_input(internet: internet), TechCheckId.reachability).status,
          TechCheckStatus.notCheckable,
        );
      }
    });

    test('a responding remote device proves the communication path', () {
      expect(
        _result(_input(connections: [_tv]), TechCheckId.reachability).status,
        TechCheckStatus.pass,
      );
      expect(
        _result(
          _input(connections: [_player('a', silentSeconds: 60)]),
          TechCheckId.reachability,
        ).status,
        TechCheckStatus.notCheckable,
      );
    });
  });

  group('players', () {
    const anna = Player(id: 'a', name: 'Anna', roundTripMicros: 40000);
    const ben = Player(id: 'b', name: 'Ben', roundTripMicros: 50000);

    test('lists missing or silent players by name', () {
      final result = _result(
        _input(
          players: [anna, ben.copyWith(isConnected: false)],
          connections: [_player('a')],
        ),
        TechCheckId.players,
      );
      expect(result.status, TechCheckStatus.warning);
      expect(result.details, ['Ben']);
    });

    test('everyone silent fails, everyone responding passes', () {
      expect(
        _result(
          _input(
            players: [anna],
            connections: [_player('a', silentSeconds: 40)],
          ),
          TechCheckId.players,
        ).status,
        TechCheckStatus.fail,
      );
      expect(
        _result(
          _input(
            players: [anna, ben],
            connections: [_player('a'), _player('b')],
          ),
          TechCheckId.players,
        ).status,
        TechCheckStatus.pass,
      );
    });
  });

  group('latency and clock sync', () {
    test('missing sync data is not checkable, never a pass', () {
      final result = _result(
        _input(
          players: const [Player(id: 'a', name: 'Anna')],
        ),
        TechCheckId.latency,
      );
      expect(result.status, TechCheckStatus.notCheckable);
    });

    test('thresholds decide between pass, warning and fail', () {
      TechCheckStatus status(int ms) => _result(
        _input(
          players: [Player(id: 'a', name: 'A', roundTripMicros: ms * 1000)],
        ),
        TechCheckId.latency,
      ).status;
      // Generous defaults for games through the internet relay.
      expect(status(250), TechCheckStatus.pass);
      expect(status(600), TechCheckStatus.warning);
      expect(status(1200), TechCheckStatus.fail);
      // Custom thresholds from the settings.
      final custom = evaluateTechCheck(
        _input(
          players: [Player(id: 'a', name: 'A', roundTripMicros: 250000)],
        ),
        thresholds: const TechCheckThresholds(
          goodRoundTrip: Duration(milliseconds: 100),
          maxRoundTrip: Duration(milliseconds: 200),
        ),
      ).firstWhere((result) => result.id == TechCheckId.latency);
      expect(custom.status, TechCheckStatus.fail);
      expect(
        const TechCheckThresholds(
          goodRoundTrip: Duration(milliseconds: 500),
          maxRoundTrip: Duration(milliseconds: 100),
        ).isValid,
        isFalse,
      );
    });

    test('a connected player without a sample turns a pass into a warning', () {
      final result = _result(
        _input(
          players: const [
            Player(id: 'a', name: 'A', roundTripMicros: 20000),
            Player(id: 'b', name: 'B'),
          ],
        ),
        TechCheckId.latency,
      );
      expect(result.status, TechCheckStatus.warning);
      expect(result.arguments.last, 1);
    });
  });

  group('tv', () {
    test('a missing TV warns but can be marked as not required', () {
      expect(_result(_input(), TechCheckId.tv).status, TechCheckStatus.warning);
      expect(
        _result(_input(tvRequired: false), TechCheckId.tv).status,
        TechCheckStatus.notRequired,
      );
      expect(
        _result(_input(connections: [_tv]), TechCheckId.tv).status,
        TechCheckStatus.pass,
      );
    });
  });

  group('media', () {
    final bytes = utf8.encode('fake audio bytes');
    final good = MediaAsset(
      id: sha256.convert(bytes).toString(),
      mimeType: 'audio/wav',
      data: base64Encode(bytes),
    );
    Question withMedia(List<MediaAttachment> media) => TrueFalseQuestion(
      id: 'm',
      prompt: 'Q',
      correctAnswer: true,
      media: media,
    );

    test('quizzes without media need no media check', () {
      expect(
        _result(_input(), TechCheckId.media).status,
        TechCheckStatus.notRequired,
      );
    });

    test('verified uploads pass; corrupt bytes fail with a next step', () {
      expect(
        _result(
          _input(
            questions: [
              withMedia([AudioAttachment(asset: good)]),
            ],
          ),
          TechCheckId.media,
        ).status,
        TechCheckStatus.pass,
      );
      final corrupt = MediaAsset(
        id: good.id,
        mimeType: 'audio/wav',
        data: base64Encode(utf8.encode('other bytes')),
      );
      final result = _result(
        _input(
          questions: [
            withMedia([AudioAttachment(asset: corrupt)]),
          ],
        ),
        TechCheckId.media,
      );
      expect(result.status, TechCheckStatus.fail);
      expect(result.details, hasLength(1));
    });

    test('online media warn because they need internet', () {
      expect(
        _result(
          _input(
            questions: [
              withMedia(const [
                VideoAttachment(youtubeId: 'aqz-KE-bpKQ'),
                GeoAttachment(latitude: 1, longitude: 2, zoom: 3),
              ]),
            ],
          ),
          TechCheckId.media,
        ).status,
        TechCheckStatus.warning,
      );
    });
  });

  test('the shareable report contains no addresses, links or codes', () {
    final results = evaluateTechCheck(
      _input(
        health: const HealthAnswered(
          address: '192.168.178.20',
          elapsed: Duration(milliseconds: 3),
        ),
        players: const [Player(id: 'p', name: 'Anna')],
      ),
    );
    final report = techCheckReport(results, (key, [args = const []]) => key);
    expect(report, isNot(contains('192.168')));
    expect(report, isNot(contains('http')));
    expect(report, contains('hostServer: pass'));
  });

  test('the report names the players affected by a problem', () {
    final results = evaluateTechCheck(
      _input(
        players: const [
          Player(id: 'p', name: 'Anna', isConnected: true),
          Player(id: 'q', name: 'Ben', isConnected: true),
        ],
        connections: [_player('p'), _player('q')],
        deviceTest: const {'p'},
      ),
    );
    final report = techCheckReport(results, (key, [args = const []]) => key);
    expect(report, contains('deviceTest: warning'));
    expect(report, contains('• Ben'));
    expect(report, isNot(contains('• Anna')));
  });

  group('device test', () {
    test('a test that was not started is not checkable', () {
      expect(
        _result(_input(), TechCheckId.deviceTest).status,
        TechCheckStatus.notCheckable,
      );
    });

    test('passes once every connected player tapped', () {
      final players = const [
        Player(id: 'p', name: 'Anna', isConnected: true),
        Player(id: 'q', name: 'Ben', isConnected: true),
        Player(id: 'r', name: 'Cem', isConnected: false),
      ];
      final waiting = _result(
        _input(players: players, deviceTest: const {}),
        TechCheckId.deviceTest,
      );
      expect(waiting.status, TechCheckStatus.warning);
      expect(waiting.details, ['Anna', 'Ben']);
      expect(
        _result(
          _input(players: players, deviceTest: const {'p', 'q'}),
          TechCheckId.deviceTest,
        ).status,
        TechCheckStatus.pass,
      );
    });
  });
}
