/// Bundled examples covering every question kind and quiz format.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../engine/scoring_rules.dart';
import '../models/models.dart';

/// Two coloured teams, enough to exercise team scoring end to end.
const Map<String, Team> sampleTeams = {
  'team-red': Team(id: 'team-red', name: 'Red Foxes', colorValue: 0xFFE5484D),
  'team-blue': Team(
    id: 'team-blue',
    name: 'Blue Whales',
    colorValue: 0xFF3E63DD,
  ),
};

/// The constant foundation shared by examples and lightweight engine clients.
const List<Question> sampleQuestionBank = [
  MultipleChoiceQuestion(
    id: 'q-capital',
    category: 'Geografie',
    prompt: 'Welche Stadt ist die Hauptstadt von Australien?',
    options: [
      AnswerOption(id: 'a', label: 'Sydney'),
      AnswerOption(id: 'b', label: 'Canberra'),
      AnswerOption(id: 'c', label: 'Melbourne'),
      AnswerOption(id: 'd', label: 'Perth'),
    ],
    correctOptionId: 'b',
    scoringRule: SpeedBonusRule(basePoints: 10, maxSpeedBonus: 10),
    timeLimit: Duration(seconds: 25),
    adminNotes: 'Einfachauswahl mit Zeitbonus. Richtige Antwort: Canberra.',
    solutionMedia: [
      GeoAttachment(
        latitude: -35.2809,
        longitude: 149.1300,
        zoom: 10,
        caption: 'Canberra – Karte erst bei der Auflösung (Internet nötig).',
      ),
    ],
  ),
  BuzzerQuestion(
    id: 'q-buzzer-element',
    category: 'Naturwissenschaft',
    prompt: 'Welches chemische Element hat das Symbol „Au“?',
    expectedAnswer: 'Gold',
    scoringRule: FirstBuzzerRule(points: 15, penalty: -5),
    timeLimit: Duration(seconds: 20),
    adminNotes:
        'Buzzer mit Sperre nach Fehler und automatischem Zeitende. '
        'Mit zwei Teams die Buzzer-Reihenfolge und den Punktabzug testen.',
  ),
  MultipleChoiceQuestion(
    id: 'q-dart',
    category: 'Technik',
    prompt:
        'Welches Dart-3-Schlüsselwort ermöglicht die vollständige '
        'Fallprüfung einer Klassenhierarchie mit switch?',
    options: [
      AnswerOption(id: 'a', label: 'abstract'),
      AnswerOption(id: 'b', label: 'sealed'),
      AnswerOption(id: 'c', label: 'mixin'),
      AnswerOption(id: 'd', label: 'extension'),
    ],
    correctOptionId: 'b',
    scoringRule: FixedPointsRule(correctPoints: 10),
    media: [
      CodeAttachment(
        code:
            'sealed class Answer {}\n'
            'final class TextAnswer extends Answer {}',
        caption: 'Dart-3-Beispiel',
      ),
    ],
    adminNotes: 'Feste Punkte ohne Zeitbonus. Code auf Spieler und TV prüfen.',
  ),
  BuzzerQuestion(
    id: 'q-buzzer-ocean',
    category: 'Geografie',
    prompt: 'Wie heißt der tiefste bekannte Punkt der Weltmeere?',
    expectedAnswer: 'Challengertief / Challenger Deep (Marianengraben)',
    scoringRule: FirstBuzzerRule(points: 20, penalty: -5, rankDecay: 8),
    lockOutOnMiss: false,
    hostEndsRound: true,
    retryLimit: 2,
    adminNotes:
        'Buzzer ohne Fehlersperre, maximal zwei Wiederholungen. '
        'Der Quizmaster beendet die Runde manuell. Rangabzug testen.',
  ),
];

/// Twelve rounds covering question kinds, media, scoring, and host controls.
final List<Question> sampleDemoQuestionBank = List.unmodifiable([
  ...sampleQuestionBank,
  MultipleChoiceQuestion(
    id: 'q-demo-multi',
    category: 'Medien',
    prompt:
        'Welche Formen sind im Bild zu sehen? Wähle alle richtigen Antworten.',
    options: const [
      AnswerOption(id: 'circle', label: 'Kreis'),
      AnswerOption(id: 'square', label: 'Quadrat'),
      AnswerOption(id: 'triangle', label: 'Dreieck'),
      AnswerOption(id: 'star', label: 'Stern'),
    ],
    allowMultipleAnswers: true,
    correctOptionIds: const ['circle', 'square'],
    scoringRule: const FixedPointsRule(correctPoints: 20, wrongPoints: -5),
    timeLimit: const Duration(seconds: 40),
    media: [
      ImageAttachment(
        asset: _sampleImage,
        caption: 'Zwei Formen',
        hideDetails: true,
      ),
    ],
    solutionMedia: [
      ImageAttachment(
        asset: _sampleImage,
        zoom: false,
        caption: 'Ein roter Kreis und ein blaues Quadrat.',
      ),
    ],
    adminNotes:
        'Mehrfachauswahl: Nur beide richtigen Formen zählen. '
        'Bild vergrößern; versteckte Bildunterschrift und Lösungsbild ohne Zoom prüfen.',
  ),
  const ShortAnswerQuestion(
    id: 'q-demo-text',
    category: 'Medien',
    prompt: 'Welches Tier steht im Mittelpunkt dieses Animationsfilms?',
    acceptedAnswers: ['Hase', 'Kaninchen', 'Bunny', 'Rabbit'],
    maxEdits: 1,
    timeLimit: Duration(seconds: 60),
    media: [
      VideoAttachment(
        youtubeId: 'aqz-KE-bpKQ',
        hideDetails: true,
        caption: 'Big Buck Bunny – Blender Foundation (CC BY 3.0)',
      ),
    ],
    solutionMedia: [
      CodeAttachment(
        language: 'text',
        code: 'Hase / Kaninchen',
        caption: 'Big Buck Bunny, Blender Foundation · https://www.bigbuckbunny.org/',
      ),
    ],
    adminNotes:
        'Verstecktes YouTube-Video (Internet nötig): Start/Pause/Neustart '
        'am Host testen. Titel bleibt für Spieler verborgen. '
        'Freitext akzeptiert Alternativen und einen Tippfehler, z. B. „Hsae“ nicht, „Hasee“ schon.',
  ),
  const OrderingQuestion(
    id: 'q-demo-order',
    category: 'Knobeln',
    prompt: 'Sortiere die Zahlen aus dem Code aufsteigend.',
    items: [
      AnswerOption(id: 'eight', label: '8'),
      AnswerOption(id: 'two', label: '2'),
      AnswerOption(id: 'five', label: '5'),
    ],
    correctOrder: ['two', 'five', 'eight'],
    media: [
      CodeAttachment(
        code: 'final zahlen = [8, 2, 5];',
        language: 'dart',
        caption: 'Reihenfolge per Ziehen oder Pfeiltasten ändern.',
      ),
    ],
    solutionMedia: [CodeAttachment(code: '[2, 5, 8]', language: 'dart')],
    timeLimit: Duration(seconds: 45),
    scoringRule: SpeedBonusRule(basePoints: 15, maxSpeedBonus: 5),
    adminNotes:
        'Reihenfolge absenden und anschließend den Lösungscode einblenden.',
  ),
  const MatchingQuestion(
    id: 'q-demo-match',
    category: 'Weltwissen',
    prompt:
        'Ordne die Hauptstädte ihren Ländern zu. Die Karte zeigt eine davon.',
    leftItems: [
      AnswerOption(id: 'de', label: 'Deutschland'),
      AnswerOption(id: 'fr', label: 'Frankreich'),
      AnswerOption(id: 'it', label: 'Italien'),
    ],
    rightItems: [
      AnswerOption(id: 'rome', label: 'Rom'),
      AnswerOption(id: 'berlin', label: 'Berlin'),
      AnswerOption(id: 'paris', label: 'Paris'),
    ],
    correctPairs: {'de': 'berlin', 'fr': 'paris', 'it': 'rome'},
    media: [
      GeoAttachment(
        latitude: 52.52,
        longitude: 13.405,
        zoom: 5,
        caption: 'Kartenausschnitt Europa (Internet nötig).',
        hideDetails: true,
      ),
    ],
    timeLimit: Duration(seconds: 50),
    adminNotes:
        'Vollständige eindeutige Zuordnung testen, auch bewusst falsch absenden. '
        'Kartenansicht mit versteckten Details prüfen.',
  ),
  const EstimationQuestion(
    id: 'q-demo-estimate',
    category: 'Weltwissen',
    prompt: 'Wie lang ist der Erdumfang am Äquator ungefähr?',
    correctValue: 40075,
    unit: 'km',
    scoringRule: FixedPointsRule(correctPoints: 100),
    timeLimit: Duration(seconds: 35),
    solutionMedia: [
      GeoAttachment(
        latitude: 0,
        longitude: 0,
        zoom: 1,
        caption: 'Die Erde: rund 40.075 km Äquatorumfang.',
      ),
    ],
    adminNotes:
        'Schätzfrage mit Einheit und anteiligen Punkten im Standardformat. '
        'Poker zahlt nur für eine vollständig korrekte Antwort aus.',
  ),
  TrueFalseQuestion(
    id: 'q-demo-audio',
    category: 'Medien',
    prompt: 'In diesem Audioclip erklingen genau drei Töne.',
    correctAnswer: true,
    media: [
      AudioAttachment(
        asset: _sampleAudio,
        playbackLimitSeconds: 2,
        hideDetails: true,
        caption: 'Drei selbst erzeugte Testtöne',
      ),
    ],
    solutionMedia: [
      AudioAttachment(
        asset: _sampleAudio,
        caption: 'Drei aufsteigende Töne, jetzt ohne Abspiellimit.',
      ),
    ],
    adminNotes:
        'Wahr/Falsch, Offline-Audio, versteckte Details und Abspiellimit. '
        'Host-Steuerung und Lösungsaudio ohne Limit testen.',
  ),
  const EstimationQuestion(
    id: 'q-demo-zero',
    category: 'Knobeln',
    prompt: 'Welchen Wert gibt der Code aus?',
    correctValue: 0,
    zeroScale: 10,
    unit: 'Punkte',
    media: [CodeAttachment(code: 'print(7 - 7);', caption: 'Zielwert null')],
    scoringRule: FixedPointsRule(correctPoints: 50),
    timeLimit: Duration(seconds: 20),
    adminNotes:
        'Zielwert 0 mit Skala 10: Im Standardformat ergeben 0 volle, '
        '5 halbe und 10 keine Punkte. Im Poker gibt es keine Teilauszahlung.',
  ),
  const TrueFalseQuestion(
    id: 'q-demo-video',
    category: 'Medien',
    prompt:
        'Dieses YouTube-Video lässt sich vollständig ohne Internet abspielen.',
    correctAnswer: false,
    media: [
      VideoAttachment(
        youtubeId: 'aqz-KE-bpKQ',
        caption: 'Big Buck Bunny – Blender Foundation (CC BY 3.0)',
      ),
    ],
    solutionMedia: [
      CodeAttachment(
        language: 'text',
        code:
            'Falsch: YouTube benötigt Internet. Eingebettete Bilder und Audio '
            'dieses Demoquiz funktionieren offline.',
        caption: 'Filmquelle: https://www.bigbuckbunny.org/',
      ),
    ],
    adminNotes:
        'Sichtbares YouTube-Video als Vergleich zum versteckten Video. '
        'Wahr/Falsch mit Lösung „Falsch“ und Lösungsmedien testen.',
  ),
]);

final _sampleImage = MediaAsset.upload(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="320" viewBox="0 0 640 320">'
      '<rect width="640" height="320" fill="#ffffff"/>'
      '<circle cx="170" cy="160" r="90" fill="#e5484d"/>'
      '<rect x="350" y="70" width="180" height="180" fill="#3e63dd"/></svg>',
    ),
  ),
  'svg',
);

final _sampleAudio = _createSampleAudio();

MediaAsset _createSampleAudio() {
  const sampleRate = 16000;
  const sampleCount = sampleRate * 2;
  final data = ByteData(44 + sampleCount * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, sampleCount * 2, Endian.little);
  for (var i = 0; i < sampleCount; i++) {
    final time = i / sampleRate;
    final tone = (time / 0.6).floor();
    final localTime = time - tone * 0.6;
    final envelope = math.min(
      1.0,
      math.min(localTime / 0.02, (0.4 - localTime) / 0.02),
    );
    final value = tone < 3 && localTime < 0.4
        ? (6000 *
                  envelope *
                  math.sin(2 * math.pi * (440 + tone * 110) * localTime))
              .round()
        : 0;
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  return MediaAsset.upload(data.buffer.asUint8List(), 'wav');
}

/// Creates the comprehensive standard-format example.
Quiz createSampleQuiz(DateTime timestamp) => Quiz(
  id: 'quiz-sample',
  name: 'Quizmo entdecken – Standard',
  description:
      '12 Fragen mit allen 7 Fragenarten: Einfach-/Mehrfachauswahl, '
      'Buzzer, Freitext, Reihenfolge, Zuordnung, Schätzen und Wahr/Falsch. '
      'Bilder, Audio, sichtbare/versteckte YouTube-Videos, Code, Karten und '
      'Lösungsmedien; Zeitbonus, Punktabzug, Buzzer-Wiederholungen und '
      'manuelles Rundenende. Testhinweise stehen in den Quizmaster-Notizen. '
      'YouTube und Karten benötigen Internet.',
  category: 'Demo',
  questions: sampleDemoQuestionBank,
  teams: sampleTeams.values.toList(growable: false),
  createdAt: timestamp.toUtc(),
  updatedAt: timestamp.toUtc(),
);

/// Creates one complete example for every supported quiz format.
List<Quiz> createSampleQuizzes(DateTime timestamp) {
  final standard = createSampleQuiz(timestamp);
  return [
    standard,
    standard.copyWith(
      id: 'quiz-sample-jeopardy',
      name: 'Quizmo entdecken – Jeopardy',
      description:
          '${standard.description} Jeopardy: 3 Kategorien × 4 Stufen '
          '(100–400 Punkte), Daily Double bei „Medien“ für 200, '
          'Punktabzug bei Fehlern und Stehlen aktiviert. '
          'Die Feldpunkte ersetzen die Punkte der einzelnen Fragen.',
      format: const JeopardyFormat(
        JeopardyBoard(
          rowPoints: [100, 200, 300, 400],
          penalizeWrongAnswers: true,
          allowSteal: true,
          categories: [
            JeopardyCategory(
              name: 'Wissen & Buzzer',
              cells: [
                JeopardyCell(questionId: 'q-capital'),
                JeopardyCell(questionId: 'q-buzzer-element'),
                JeopardyCell(questionId: 'q-dart'),
                JeopardyCell(questionId: 'q-buzzer-ocean'),
              ],
            ),
            JeopardyCategory(
              name: 'Medien',
              cells: [
                JeopardyCell(questionId: 'q-demo-multi'),
                JeopardyCell(questionId: 'q-demo-text', isDailyDouble: true),
                JeopardyCell(questionId: 'q-demo-audio'),
                JeopardyCell(questionId: 'q-demo-video'),
              ],
            ),
            JeopardyCategory(
              name: 'Knobeln & Welt',
              cells: [
                JeopardyCell(questionId: 'q-demo-order'),
                JeopardyCell(questionId: 'q-demo-match'),
                JeopardyCell(questionId: 'q-demo-estimate'),
                JeopardyCell(questionId: 'q-demo-zero'),
              ],
            ),
          ],
        ),
      ),
    ),
    standard.copyWith(
      id: 'quiz-sample-poker',
      name: 'Quizmo entdecken – Pokerchips',
      description:
          '${standard.description} Pokerchips: 250 Startchips je Team. '
          'Vor jeder Frage Einsätze abgeben und Setzphase am Host schließen. '
          'Richtig zahlt den doppelten Einsatz; falsch oder ohne Antwort '
          'verliert den Einsatz. Einsatz 0 überspringt die Frage. '
          'Frage-Punktregeln gelten hier nicht.',
      format: const PokerFormat(startingChips: 250),
    ),
  ];
}
