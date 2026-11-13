/// Technical readiness check before a game starts.
///
/// Pure Dart: the host collects the raw facts (server state, a timed health
/// request, connected sockets, clock sync samples, media) and this file turns
/// them into findings with a status and a concrete next step. It never
/// changes the game or any score.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/media_attachment.dart';
import '../models/player.dart';
import '../models/question.dart';

/// Outcome of one check.
enum TechCheckStatus {
  /// Verified to work.
  pass,

  /// Works, but something deserves attention.
  warning,

  /// Does not work.
  fail,

  /// No data to decide; never counts as success.
  notCheckable,

  /// The host marked the check as not needed (e.g. no TV in this game).
  notRequired,
}

/// The individual checks.
enum TechCheckId {
  hostServer,
  webPlayer,
  reachability,
  players,
  deviceTest,
  latency,
  tv,
  media,
}

/// One finding.
final class TechCheckResult {
  /// Creates a finding.
  const TechCheckResult({
    required this.id,
    required this.status,
    required this.summary,
    required this.nextStep,
    this.arguments = const [],
    this.details = const [],
  });

  /// The check.
  final TechCheckId id;

  /// Its outcome.
  final TechCheckStatus status;

  /// Message key describing the outcome; may contain `{0}` placeholders.
  final String summary;

  /// Values for the placeholders of [summary].
  final List<Object?> arguments;

  /// Message key with the recommended next step.
  final String nextStep;

  /// Extra lines (names of affected devices or media); never secrets.
  final List<String> details;
}

/// Thresholds the latency check uses; shown to the host with the result.
///
/// LAN and internet games have their own defaults ([lan], [internet]):
/// through the relay a few hundred milliseconds are normal. Hosts can change
/// both in the settings.
final class TechCheckThresholds {
  /// Creates thresholds (internet defaults unless given).
  const TechCheckThresholds({
    this.goodRoundTrip = const Duration(milliseconds: defaultGoodMs),
    this.maxRoundTrip = const Duration(milliseconds: defaultMaxMs),
    this.silentAfter = const Duration(seconds: 15),
  });

  /// Defaults for games on the LAN server: good up to 150 ms, error above
  /// 400 ms.
  static const lan = TechCheckThresholds(
    goodRoundTrip: Duration(milliseconds: lanGoodMs),
    maxRoundTrip: Duration(milliseconds: lanMaxMs),
  );

  /// Defaults for games through the internet relay: good up to 300 ms,
  /// error above 1000 ms.
  static const internet = TechCheckThresholds();

  /// Default for [goodRoundTrip] on the LAN in milliseconds.
  static const lanGoodMs = 150;

  /// Default for [maxRoundTrip] on the LAN in milliseconds.
  static const lanMaxMs = 400;

  /// Defaults of the given mode.
  static TechCheckThresholds defaultsFor({required bool internet}) =>
      internet ? TechCheckThresholds.internet : TechCheckThresholds.lan;

  /// Round trips up to this value are fine.
  final Duration goodRoundTrip;

  /// Round trips above this value fail; between both values is a warning.
  final Duration maxRoundTrip;

  /// A socket without any frame for this long counts as not responding.
  final Duration silentAfter;

  /// Default for [goodRoundTrip] in milliseconds.
  static const defaultGoodMs = 300;

  /// Default for [maxRoundTrip] in milliseconds.
  static const defaultMaxMs = 1000;

  /// Whether the values can be used: both positive and good ≤ limit.
  bool get isValid =>
      goodRoundTrip > Duration.zero && maxRoundTrip >= goodRoundTrip;
}

/// Kind of an open socket.
enum TechCheckConnectionKind { player, spectator, lobby }

/// A socket currently open on the host.
final class TechCheckConnection {
  /// Creates a connection fact.
  const TechCheckConnection({
    required this.kind,
    required this.silentFor,
    this.playerId,
  });

  /// What the socket is used for.
  final TechCheckConnectionKind kind;

  /// Player behind a player socket.
  final String? playerId;

  /// Time since the last frame arrived (heartbeats included).
  final Duration silentFor;
}

/// Result of the timed health request the host sends to its own address.
sealed class HealthProbe {
  const HealthProbe();
}

/// The probe was not run (e.g. the server is stopped).
final class HealthNotRun extends HealthProbe {
  /// Creates the value.
  const HealthNotRun();
}

/// The server answered.
final class HealthAnswered extends HealthProbe {
  /// Creates the value.
  const HealthAnswered({required this.address, required this.elapsed});

  /// Address that was asked; only used locally, never in a report.
  final String address;

  /// Time until the answer.
  final Duration elapsed;
}

/// The probe failed or timed out.
final class HealthFailed extends HealthProbe {
  /// Creates the value.
  const HealthFailed({required this.timedOut});

  /// Whether the time limit ran out.
  final bool timedOut;
}

/// All facts the evaluation needs.
final class TechCheckInput {
  /// Creates the input.
  const TechCheckInput({
    required this.serverRunning,
    required this.internet,
    required this.health,
    required this.players,
    required this.connections,
    required this.questions,
    this.tvRequired = true,
    this.mediaRequired = true,
    this.deviceTestConfirmed,
    this.deviceTestScreens = 0,
    this.outdatedWebPlayer,
  });

  /// Whether the host server (LAN) or relay room (internet) is up.
  final bool serverRunning;

  /// Whether the game runs through the internet relay.
  final bool internet;

  /// Result of the host's own health request.
  final HealthProbe health;

  /// Roster with clock sync samples.
  final List<Player> players;

  /// Open sockets.
  final List<TechCheckConnection> connections;

  /// Questions of the quiz (for the media check).
  final List<Question> questions;

  /// Whether a TV is part of this game.
  final bool tvRequired;

  /// Whether the media check matters for this game.
  final bool mediaRequired;

  /// Players whose device confirmed the running device test (a tap on the
  /// device); `null` while no device test runs.
  final Set<String>? deviceTestConfirmed;

  /// TV screens that show (and confirmed) the running device test.
  final int deviceTestScreens;

  /// Version of the packed web player when it differs from the host app,
  /// `null` when it matches or cannot be read.
  final String? outdatedWebPlayer;
}

/// Media of a quiz as seen by the media check.
final class MediaCheckSummary {
  /// Creates a summary.
  const MediaCheckSummary({
    required this.uploads,
    required this.broken,
    required this.online,
  });

  /// Number of embedded uploads that verified.
  final int uploads;

  /// Labels of uploads whose bytes are missing or do not match their id.
  final List<String> broken;

  /// Labels of attachments that need internet (YouTube, maps).
  final List<String> online;

  /// Whether the quiz uses any playable or online media at all.
  bool get isEmpty => uploads == 0 && broken.isEmpty && online.isEmpty;
}

/// Verifies every embedded upload and lists online media of [questions].
MediaCheckSummary checkQuizMedia(List<Question> questions) {
  var uploads = 0;
  final broken = <String>[];
  final online = <String>[];
  for (final question in questions) {
    for (final media in [...question.media, ...question.solutionMedia]) {
      final label = '${question.id}: ${media.runtimeType}';
      switch (media) {
        case VideoAttachment(youtubeId: final _?):
          online.add(label);
          continue;
        case GeoAttachment():
          online.add(label);
          continue;
        case _:
          break;
      }
      final asset = media.asset;
      if (asset == null) continue;
      final data = asset.data;
      var valid = false;
      if (data != null) {
        try {
          valid = sha256.convert(base64Decode(data)).toString() == asset.id;
        } on FormatException {
          valid = false;
        }
      }
      if (valid) {
        uploads++;
      } else {
        broken.add(label);
      }
    }
  }
  return MediaCheckSummary(uploads: uploads, broken: broken, online: online);
}

/// Evaluates every check.
List<TechCheckResult> evaluateTechCheck(
  TechCheckInput input, {
  TechCheckThresholds thresholds = const TechCheckThresholds(),
}) => [
  _hostServer(input),
  _webPlayer(input),
  _reachability(input, thresholds),
  _players(input, thresholds),
  _deviceTest(input),
  _latency(input, thresholds),
  _tv(input, thresholds),
  _media(input),
];

TechCheckResult _hostServer(TechCheckInput input) {
  if (!input.serverRunning) {
    return TechCheckResult(
      id: TechCheckId.hostServer,
      status: TechCheckStatus.fail,
      summary: input.internet
          ? 'Der Internet-Raum ist nicht verbunden.'
          : 'Der Host-Server läuft nicht.',
      nextStep: 'Server im Bereich „Server“ starten und erneut prüfen.',
    );
  }
  if (input.internet) {
    return const TechCheckResult(
      id: TechCheckId.hostServer,
      status: TechCheckStatus.pass,
      summary: 'Der Internet-Raum ist mit dem Relay verbunden.',
      nextStep: 'Nichts zu tun.',
    );
  }
  return switch (input.health) {
    HealthAnswered(:final elapsed) => TechCheckResult(
      id: TechCheckId.hostServer,
      status: TechCheckStatus.pass,
      summary: 'Der Host-Server antwortet in {0} ms.',
      arguments: [elapsed.inMilliseconds],
      nextStep: 'Nichts zu tun.',
    ),
    HealthFailed(:final timedOut) => TechCheckResult(
      id: TechCheckId.hostServer,
      status: TechCheckStatus.fail,
      summary: timedOut
          ? 'Der Host-Server antwortet nicht innerhalb des Zeitlimits.'
          : 'Der Host-Server ist unter seiner LAN-Adresse nicht erreichbar.',
      nextStep: 'Firewall des Host-Geräts prüfen, eine andere angezeigte Adresse wählen oder den Server neu starten.',
    ),
    HealthNotRun() => const TechCheckResult(
      id: TechCheckId.hostServer,
      status: TechCheckStatus.notCheckable,
      summary: 'Die Server-Prüfung wurde noch nicht ausgeführt.',
      nextStep: 'Prüfung starten.',
    ),
  };
}

TechCheckResult _reachability(
  TechCheckInput input,
  TechCheckThresholds thresholds,
) {
  final remote = input.connections.where(
    (c) =>
        c.kind != TechCheckConnectionKind.lobby &&
        c.silentFor <= thresholds.silentAfter,
  );
  if (remote.isNotEmpty) {
    return TechCheckResult(
      id: TechCheckId.reachability,
      status: TechCheckStatus.pass,
      summary: '{0} Gerät(e) sind tatsächlich verbunden und antworten.',
      arguments: [remote.length],
      nextStep: 'Nichts zu tun.',
    );
  }
  // A local health answer proves nothing about guests (firewall, client
  // isolation, mobile data, a wrong address), so it never passes this check.
  return TechCheckResult(
    id: TechCheckId.reachability,
    status: TechCheckStatus.notCheckable,
    summary: input.internet
        ? 'Externe Erreichbarkeit ungeprüft: Noch kein Gerät ist über den Einladungslink verbunden.'
        : 'Externe Erreichbarkeit ungeprüft: Ein lokaler Test beweist nicht, dass Gäste den Host erreichen.',
    nextStep: input.internet
        ? 'Mit einem Smartphone über den Einladungslink beitreten.'
        : 'Mit einem Smartphone im selben WLAN über den QR-Code beitreten. Klappt das nicht: andere Adresse wählen, Firewall und Gäste-Isolation des WLANs prüfen.',
  );
}

TechCheckResult _players(TechCheckInput input, TechCheckThresholds thresholds) {
  if (input.players.isEmpty) {
    return const TechCheckResult(
      id: TechCheckId.players,
      status: TechCheckStatus.warning,
      summary: 'Noch keine Spieler beigetreten.',
      nextStep: 'Spieler über den QR-Code oder Link beitreten lassen.',
    );
  }
  final responsive = {
    for (final connection in input.connections)
      if (connection.kind == TechCheckConnectionKind.player &&
          connection.silentFor <= thresholds.silentAfter)
        ?connection.playerId,
  };
  final missing = [
    for (final player in input.players)
      if (!player.isConnected || !responsive.contains(player.id)) player.name,
  ];
  if (missing.isEmpty) {
    return TechCheckResult(
      id: TechCheckId.players,
      status: TechCheckStatus.pass,
      summary: 'Alle {0} Spieler sind verbunden.',
      arguments: [input.players.length],
      nextStep: 'Nichts zu tun.',
    );
  }
  return TechCheckResult(
    id: TechCheckId.players,
    status: missing.length == input.players.length
        ? TechCheckStatus.fail
        : TechCheckStatus.warning,
    summary: '{0} von {1} Spielern sind nicht verbunden oder antworten nicht.',
    arguments: [missing.length, input.players.length],
    nextStep: 'Betroffene Geräte neu laden lassen (Seite bleibt im selben Spiel) oder Spieler entfernen.',
    details: missing,
  );
}

TechCheckResult _deviceTest(TechCheckInput input) {
  final confirmed = input.deviceTestConfirmed;
  if (confirmed == null) {
    return const TechCheckResult(
      id: TechCheckId.deviceTest,
      status: TechCheckStatus.notCheckable,
      summary: 'Der Gerätetest wurde noch nicht gestartet.',
      nextStep: '„Gerätetest starten“ wählen: Alle Spieler tippen einmal auf ihrem Gerät, verbundene TVs zeigen den Test an.',
    );
  }
  final screens = input.deviceTestScreens;
  final connected = input.players.where((p) => p.isConnected).toList();
  if (connected.isEmpty) {
    return TechCheckResult(
      id: TechCheckId.deviceTest,
      status: TechCheckStatus.notCheckable,
      summary: 'Kein verbundener Spieler für den Gerätetest; {0} TV-Ansicht(en) zeigen den Test.',
      arguments: [screens],
      nextStep: 'Spieler über den QR-Code oder Link beitreten lassen.',
    );
  }
  final missing = [
    for (final player in connected)
      if (!confirmed.contains(player.id)) player.name,
  ];
  if (missing.isEmpty) {
    return TechCheckResult(
      id: TechCheckId.deviceTest,
      status: TechCheckStatus.pass,
      summary: 'Alle {0} Spieler haben ihr Gerät bestätigt; {1} TV-Ansicht(en) zeigen den Test.',
      arguments: [connected.length, screens],
      nextStep: 'Nichts zu tun.',
    );
  }
  return TechCheckResult(
    id: TechCheckId.deviceTest,
    status: TechCheckStatus.warning,
    summary: '{0} von {1} Spielern haben noch nicht getippt; {2} TV-Ansicht(en) zeigen den Test.',
    arguments: [missing.length, connected.length, screens],
    nextStep: 'Betroffene Spieler bitten, auf „Hier tippen“ zu tippen. Erscheint der Knopf nicht, die Seite neu laden.',
    details: missing,
  );
}

TechCheckResult _latency(TechCheckInput input, TechCheckThresholds thresholds) {
  final connected = input.players.where((p) => p.isConnected).toList();
  final measured = connected.where((p) => p.roundTripMicros > 0).toList();
  if (measured.isEmpty) {
    return const TechCheckResult(
      id: TechCheckId.latency,
      status: TechCheckStatus.notCheckable,
      summary: 'Keine Messwerte zur Uhrensynchronisation vorhanden.',
      nextStep: 'Warten, bis Spieler verbunden sind; die Messung läuft beim Beitritt automatisch.',
    );
  }
  final slow = [
    for (final player in measured)
      if (Duration(microseconds: player.roundTripMicros) >
          thresholds.maxRoundTrip)
        player,
  ];
  final sluggish = [
    for (final player in measured)
      if (Duration(microseconds: player.roundTripMicros) >
              thresholds.goodRoundTrip &&
          !slow.contains(player))
        player,
  ];
  final unmeasured = connected.length - measured.length;
  final worst = measured
      .map((p) => p.roundTripMicros)
      .reduce((a, b) => a > b ? a : b);
  final details = [
    for (final player in [...slow, ...sluggish])
      '${player.name}: ${player.roundTripMicros ~/ 1000} ms',
  ];
  final status = slow.isNotEmpty
      ? TechCheckStatus.fail
      : sluggish.isNotEmpty || unmeasured > 0
      ? TechCheckStatus.warning
      : TechCheckStatus.pass;
  return TechCheckResult(
    id: TechCheckId.latency,
    status: status,
    summary: 'Höchste Laufzeit {0} ms (gut bis {1} ms, Grenze {2} ms); {3} Gerät(e) ohne Messwert.',
    arguments: [
      worst ~/ 1000,
      thresholds.goodRoundTrip.inMilliseconds,
      thresholds.maxRoundTrip.inMilliseconds,
      unmeasured,
    ],
    nextStep: status == TechCheckStatus.pass ? 'Nichts zu tun.' : 'Betroffene Geräte näher an den Router bringen, ins selbe WLAN statt mobile Daten wechseln oder neu verbinden. Buzzer bleiben dank Uhrensynchronisation fair.',
    details: details,
  );
}

TechCheckResult _tv(TechCheckInput input, TechCheckThresholds thresholds) {
  if (!input.tvRequired) {
    return const TechCheckResult(
      id: TechCheckId.tv,
      status: TechCheckStatus.notRequired,
      summary: 'Für dieses Spiel als nicht erforderlich markiert.',
      nextStep: 'Nichts zu tun.',
    );
  }
  final tvs = input.connections.where(
    (c) => c.kind == TechCheckConnectionKind.spectator,
  );
  final responsive = tvs.where((c) => c.silentFor <= thresholds.silentAfter);
  if (responsive.isNotEmpty) {
    return TechCheckResult(
      id: TechCheckId.tv,
      status: TechCheckStatus.pass,
      summary: '{0} TV-Ansicht(en) verbunden.',
      arguments: [responsive.length],
      nextStep: 'Nichts zu tun.',
    );
  }
  return TechCheckResult(
    id: TechCheckId.tv,
    status: tvs.isEmpty ? TechCheckStatus.warning : TechCheckStatus.fail,
    summary: tvs.isEmpty
        ? 'Keine TV-Ansicht verbunden.'
        : 'Die TV-Ansicht antwortet nicht.',
    nextStep: 'Auf dem TV die TV-Adresse öffnen (QR-Code im Bereich „Server“) oder den Check als nicht erforderlich markieren.',
  );
}

TechCheckResult _media(TechCheckInput input) {
  if (!input.mediaRequired) {
    return const TechCheckResult(
      id: TechCheckId.media,
      status: TechCheckStatus.notRequired,
      summary: 'Für dieses Spiel als nicht erforderlich markiert.',
      nextStep: 'Nichts zu tun.',
    );
  }
  final summary = checkQuizMedia(input.questions);
  if (summary.isEmpty) {
    return const TechCheckResult(
      id: TechCheckId.media,
      status: TechCheckStatus.notRequired,
      summary: 'Das Quiz enthält keine Medien.',
      nextStep: 'Nichts zu tun.',
    );
  }
  if (summary.broken.isNotEmpty) {
    return TechCheckResult(
      id: TechCheckId.media,
      status: TechCheckStatus.fail,
      summary: '{0} Mediendatei(en) sind beschädigt oder fehlen.',
      arguments: [summary.broken.length],
      nextStep:
          'Medium im Quiz-Editor erneut hochladen und das Quiz speichern.',
      details: summary.broken,
    );
  }
  return TechCheckResult(
    id: TechCheckId.media,
    status: summary.online.isEmpty
        ? TechCheckStatus.pass
        : TechCheckStatus.warning,
    summary: summary.online.isEmpty
        ? '{0} eingebettete Mediendatei(en) sind vollständig.'
        : '{0} eingebettete Mediendatei(en) sind vollständig; {1} Anhang/Anhänge brauchen Internet (YouTube, Karten).',
    arguments: [summary.uploads, summary.online.length],
    nextStep: summary.online.isEmpty
        ? 'Wiedergabe einmal mit „Testwiedergabe“ ausprobieren; Browser erlauben Ton oft erst nach einem Tippen.'
        : 'Internetzugang von TV und Spielern prüfen und die Wiedergabe einmal ausprobieren.',
    details: summary.online,
  );
}

/// Plain text report that is safe to share: statuses, generic messages and,
/// for problems, the affected players or media (names only). Room links,
/// join codes, addresses and resume tokens never appear, because
/// [TechCheckResult]s never carry them.
String techCheckReport(
  List<TechCheckResult> results,
  String Function(String key, [List<Object?> arguments]) tr,
) => [
  for (final result in results)
    [
      '${result.id.name}: ${result.status.name}',
      '  ${tr(result.summary, result.arguments)}',
      '  → ${tr(result.nextStep)}',
      if (result.status != TechCheckStatus.pass &&
          result.status != TechCheckStatus.notRequired)
        for (final detail in result.details) '    • $detail',
    ].join('\n'),
].join('\n');

TechCheckResult _webPlayer(TechCheckInput input) {
  if (input.internet) {
    return const TechCheckResult(
      id: TechCheckId.webPlayer,
      status: TechCheckStatus.notRequired,
      summary: 'Im Internetbetrieb liefert der Server den Web-Player aus.',
      nextStep: 'Nichts zu tun.',
    );
  }
  if (input.outdatedWebPlayer case final version?) {
    return TechCheckResult(
      id: TechCheckId.webPlayer,
      status: TechCheckStatus.fail,
      summary:
          'Der eingebaute Web-Player ist veraltet ({0}); Spieler- und TV-Browser sehen neue Funktionen nicht.',
      arguments: [version],
      nextStep:
          '„dart run tool/bundle_web_client.dart“ ausführen und den Host danach neu starten oder bauen.',
    );
  }
  return const TechCheckResult(
    id: TechCheckId.webPlayer,
    status: TechCheckStatus.pass,
    summary: 'Der Web-Player passt zur Version des Hosts.',
    nextStep: 'Nichts zu tun.',
  );
}
