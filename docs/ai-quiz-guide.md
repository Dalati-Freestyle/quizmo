# Quizmo-Quiz mit einem KI-Assistenten erstellen

<!--
  Diese Datei ist gleichzeitig die Anleitung im Repository und die Datei, die
  Quizmo unter Einstellungen → „Quiz mit KI erstellen“ ausliefert (Asset).
  test/core/data/ai_quiz_guide_test.dart importiert jedes Beispiel unten und
  schlägt fehl, sobald sich die schemaVersion ändert. Dann diese Anleitung an
  das neue Schema anpassen.
-->

Quizmo-Schema-Version dieser Anleitung: **7**

**Anleitung für den KI-Assistenten.** Du hilfst der Person, mit der du sprichst,
ein Quiz für die Quiz-App *Quizmo* zu erstellen. Am Ende des Gesprächs gibst du
**eine einzige, gültige Datei `<name>.quizmo.json`** aus, die sich in Quizmo
direkt importieren lässt (Quiz-Bibliothek → „Importieren“). Antworte in der
Sprache der Person. Du brauchst keinen Zugriff auf den Quellcode von Quizmo;
alles Nötige steht hier.

## 1. Gesprächsablauf

### Einstieg

Erkläre in zwei, drei Sätzen, wie es abläuft, und frage dann **zuerst**:

> „Soll ich das Quiz **vollautomatisch** erstellen (du nennst mir nur das Thema
> und ich entscheide alles andere), oder wollen wir es **gemeinsam Schritt für
> Schritt** aufbauen?“

### Vollautomatischer Modus

* Stelle höchstens die nötigsten Rückfragen (in der Regel nur: Thema; ggf.
  Sprache oder Zielgruppe, falls nicht erkennbar).
* Entscheide alles andere selbst: Format, Teams oder Solo, Zeitlimits, Wertung,
  Anzahl und Art der Fragen (gemischt, mindestens drei verschiedene Fragetypen).
* Gib danach sofort die fertige Datei aus.

### Geführter Modus

Kläre **zuerst alles, was sich durch das ganze Quiz zieht**, bevor die erste
Frage entsteht. Frage aktiv nach und schlage sinnvolle Standards vor:

1. **Quizformat** – Standard, Jeopardy oder Pokerchips (siehe Abschnitt 3)
   samt formatspezifischer Regeln (Board-Aufbau, Minuspunkte, Steal, Startchips,
   Auflösung nach jeder Frage oder am Ende).
2. **Teams oder Solo** – vordefinierte Teams (Namen, Farben) oder Einzelspieler.
3. **Zeitlimits** – Standard-Zeit pro Frage, hartes oder weiches Limit.
4. **Wertung** – feste Punkte, Geschwindigkeitsbonus, Buzzer-Wertung,
   Minuspunkte bei falscher Antwort.
5. **Inhalt** – Thema, Zielgruppe, Schwierigkeit, Sprache, Anzahl der Fragen
   und gewünschte Fragetypen.

Fasse die Entscheidungen kurz zusammen und lass sie bestätigen.

Gehe danach **Frage für Frage** vor und frage ruhig viel nach, statt still
Annahmen zu treffen: Fragetyp, Fragetext, Lösung, Antwortoptionen, Punkte und
Abweichungen von den allgemeinen Einstellungen (anderes Zeitlimit, andere
Wertung, Kategorie, Notiz für die Spielleitung). Zeige jede Frage kurz zur
Bestätigung, bevor du zur nächsten gehst.

### Abschluss

1. Prüfe die Datei selbst gegen die Checkliste in Abschnitt 7.
2. Gib sie als **einen einzigen** ```` ```json ```` Codeblock aus (oder als
   Datei-Download, falls dein Werkzeug das kann). Keine Kommentare im JSON.
3. Schreibe darunter kurz, wie man importiert: Datei als `<name>.quizmo.json`
   speichern → Quizmo öffnen → Quiz-Bibliothek → „Importieren“ → Datei wählen.
   Bilder, Audio und Videos lassen sich danach im Quiz-Editor ergänzen.

## 2. Aufbau der Datei

```text
{
  "schemaVersion": 7,               // immer genau 7
  "id": "quiz-…",                   // eindeutige ID, nur a-z, 0-9 und -
  "name": "Titel",
  "description": "Kurze Beschreibung (nicht leer)",
  "category": "Kategorie (nicht leer)",
  "questions": [ … ],               // siehe Abschnitt 4
  "teams": [ … ],                   // leer = Solo (bei Poker: Teams entstehen beim Beitritt)
  "format": { … },                  // siehe Abschnitt 3
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

* `createdAtMicros` / `updatedAtMicros`: Zeitpunkt in Mikrosekunden seit
  1970 (UTC). Nimm den aktuellen Zeitpunkt; `updatedAtMicros` darf nicht vor
  `createdAtMicros` liegen.
* Team: `{"id": "team-rot", "name": "Rot", "colorValue": 4293212469}` –
  `colorValue` ist eine ARGB-Farbe als Dezimalzahl (z. B. `0xFFE53935` =
  `4293212469`, `0xFF1E88E5` = `4280191205`, `0xFF43A047` = `4282622023`,
  `0xFFFDD835` = `4294826037`).
* Alle IDs (Quiz, Teams, Fragen, Optionen) sind innerhalb ihrer Liste eindeutig.

## 3. Quizformate

| Format | `format` | Hinweise |
| --- | --- | --- |
| Standard | `{"type": "standard", "revealMode": "afterEachQuestion"}` | Fragen der Reihe nach. `revealMode`: `afterEachQuestion` (Lösung nach jeder Frage) oder `atEnd` (alle Lösungen und Punkte erst am Ende). |
| Jeopardy | `{"type": "jeopardy", "board": { … }}` | Board aus Kategorien (Spalten) × Zeilen. Punkte kommen aus der Zeile, nicht aus der Frage. |
| Pokerchips | `{"type": "poker", "startingChips": 100}` | Teams setzen vor jeder Frage Chips (1–1.000.000 Startchips). Richtig = doppelter Einsatz zurück, falsch = Einsatz weg. `teams` darf leer sein. |

**Jeopardy-Board:**

```text
"board": {
  "categories": [
    {"name": "Kategorie A", "cells": [
      {"questionId": "a1", "dailyDouble": false},   // Zeile 1
      {"questionId": "a2", "dailyDouble": true}     // Zeile 2
    ]}
  ],
  "rowPoints": [100, 200],          // Punkte je Zeile, alle > 0
  "penalizeWrongAnswers": false,    // falsche Antwort kostet die Zeilenpunkte
  "allowSteal": true                // nach einem Fehler dürfen andere Teams antworten
}
```

* Jede Zelle verweist per `questionId` auf eine Frage aus `questions`; jede Frage
  steht höchstens einmal auf dem Board. Eine Kategorie hat höchstens so viele
  Zellen wie `rowPoints` Einträge hat.
* Jeopardy wird mit Teams gespielt: lege mindestens zwei Teams an.
* Jeder Fragetyp funktioniert in jedem Format.

## 4. Gemeinsame Felder jeder Frage

```text
{
  "type": "…",                  // siehe Abschnitt 5
  "id": "q1",                   // eindeutig
  "prompt": "Fragetext",
  "timeLimitMs": 30000,         // > 0, in Millisekunden
  "softTimeLimit": false,       // true = Runde bleibt nach Ablauf offen, bis die Spielleitung beendet
  "category": "Geschichte",     // optional, sonst null
  "adminNotes": "",             // Notiz nur für die Spielleitung
  "media": [],                  // Anhänge zur Frage (Abschnitt 6)
  "solutionMedia": [],          // Anhänge, die erst mit der Lösung erscheinen
  "scoringRule": { … }          // Wertung, siehe unten
}
```

**Wertung (`scoringRule`):**

| Regel | JSON | Bedeutung |
| --- | --- | --- |
| Feste Punkte | `{"type": "fixed", "correctPoints": 10, "wrongPoints": 0}` | Richtig = `correctPoints`; falsch = `wrongPoints` (0 oder negativ). |
| Geschwindigkeitsbonus | `{"type": "speedBonus", "basePoints": 10, "maxSpeedBonus": 10, "wrongPoints": 0}` | Grundpunkte plus Bonus, je schneller die Antwort. |
| Buzzer | `{"type": "firstBuzzer", "points": 15, "penalty": -5, "rankDecay": 5}` | Für Buzzerfragen: Punkte für richtig, `penalty` für falsch, `rankDecay` Abzug pro späterem Rang. |

Bei Schätzfragen werden die Punkte anteilig nach Genauigkeit vergeben. Auf einem
Jeopardy-Board und im Pokerformat ersetzt das Format die Punkte; gib trotzdem
eine gültige `scoringRule` an (z. B. `fixed` mit 10/0).

## 5. Fragetypen

| `type` | Zusätzliche Felder | Regeln |
| --- | --- | --- |
| `multipleChoice` | `options` (Liste `{"id","label"}`), `correctOptionId`, `correctOptionIds`, `allowMultipleAnswers` | Mindestens 2 Optionen. Einfachauswahl: `correctOptionId` = ID, `correctOptionIds` = `null`, `allowMultipleAnswers` = `false`. Mehrfachauswahl: `correctOptionId` = `null`, `correctOptionIds` = Liste, `allowMultipleAnswers` = `true`. |
| `buzzer` | `expectedAnswer`, `lockOutOnMiss`, `hostEndsRound`, `retryLimit` | Wer zuerst buzzert, antwortet mündlich; die Spielleitung bewertet. `retryLimit`: `null` = unbegrenzt, sonst ≥ 0. Wertung meist `firstBuzzer`. |
| `shortAnswer` | `acceptedAnswers` (Liste), `maxEdits` (0–5), `manualGrading` | Freitext. Mindestens eine akzeptierte Antwort. `maxEdits` = erlaubte Tippfehler. `manualGrading: true` = Spielleitung bewertet von Hand. |
| `ordering` | `items` (Liste `{"id","label"}`), `correctOrder` (Liste der IDs) | Reihenfolge. Mindestens 2 Elemente; `correctOrder` enthält jede ID genau einmal. |
| `matching` | `leftItems`, `rightItems` (je Liste `{"id","label"}`), `correctPairs` (`{"linkeId": "rechteId"}`) | Zuordnung. Jede linke ID genau einem eindeutigen rechten Partner zuordnen. |
| `estimation` | `correctValue` (Zahl), `zeroScale` (> 0), `unit` | Schätzfrage. Punkte anteilig `max(0, 1 − |Antwort − Ziel| / |Ziel|)`; bei Ziel 0 ersetzt `zeroScale` den Nenner. |
| `trueFalse` | `correctAnswer` (`true`/`false`) | Wahr/Falsch. |

## 6. Medien

Eingebettete Dateien (Bilder, Audio, MP4) enthalten Base64-Daten mit SHA-256-ID.
**Erzeuge solche Uploads nicht** – das kann ein Chat-Modell nicht zuverlässig.
Lass `media`/`solutionMedia` leer oder verwende nur diese Referenzen ohne
Dateiinhalt, und sag der Person, dass Bilder und Audio im Quiz-Editor ergänzt
werden:

| Art | JSON |
| --- | --- |
| YouTube-Video | `{"type": "video", "caption": "", "hideDetails": false, "asset": null, "youtubeId": "aqz-KE-bpKQ"}` – nur die Video-ID; nur echte, existierende Videos verwenden. Braucht Internet. |
| Kartenausschnitt | `{"type": "geo", "caption": "Berlin", "hideDetails": false, "latitude": 52.52, "longitude": 13.405, "zoom": 10.0}` – OpenStreetMap, braucht Internet. |
| Code/Text | `{"type": "code", "caption": "", "hideDetails": false, "code": "print(1 + 1);", "language": "dart"}` – Syntaxhervorhebung; `language` z. B. `dart`, `python`, `javascript`, `text`. |

`hideDetails: true` verbirgt Beschriftung/Titel auf Spieler- und TV-Geräten.
Höchstens 10 Anhänge pro Frage (Frage und Lösung zusammen).

## 7. Checkliste vor der Ausgabe

- [ ] `"schemaVersion": 7` steht ganz oben.
- [ ] `name`, `description` und `category` sind nicht leer.
- [ ] Alle IDs sind eindeutig und nicht leer.
- [ ] Jede Frage hat einen Text, ein Zeitlimit > 0 und eine gültige `scoringRule`.
- [ ] Jede Frage hat eine vollständige, gültige Lösung (siehe Abschnitt 5).
- [ ] Jeopardy: Jede `questionId` existiert, keine Frage doppelt, Zeilenpunkte > 0,
      jede Kategorie hat einen Namen, mindestens zwei Teams.
- [ ] Poker: `startingChips` zwischen 1 und 1.000.000.
- [ ] Teams haben `id`, `name` und `colorValue`.
- [ ] Keine Upload-Medien (`asset` mit Daten); nur YouTube, Karte, Code.
- [ ] Gültiges JSON: doppelte Anführungszeichen, keine Kommentare, keine
      nachgestellten Kommas.

## 8. Vollständige Beispiele

Die folgenden Dateien sind gültig und lassen sich unverändert importieren.

### Standard (Solo, alle Fragetypen)

```json quizmo-example
{
  "schemaVersion": 7,
  "id": "quiz-ki-standard-beispiel",
  "name": "Allgemeinwissen kompakt",
  "description": "Sieben Fragen mit allen Fragetypen.",
  "category": "Allgemeinwissen",
  "questions": [
    {
      "type": "multipleChoice",
      "id": "q-hauptstadt",
      "prompt": "Welche Stadt ist die Hauptstadt von Kanada?",
      "timeLimitMs": 25000,
      "softTimeLimit": false,
      "category": "Geografie",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [
        {"type": "geo", "caption": "Ottawa", "hideDetails": false, "latitude": 45.4215, "longitude": -75.6972, "zoom": 9.0}
      ],
      "scoringRule": {"type": "speedBonus", "basePoints": 10, "maxSpeedBonus": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Toronto"},
        {"id": "b", "label": "Ottawa"},
        {"id": "c", "label": "Vancouver"},
        {"id": "d", "label": "Montreal"}
      ],
      "correctOptionId": "b",
      "correctOptionIds": null,
      "allowMultipleAnswers": false
    },
    {
      "type": "multipleChoice",
      "id": "q-primzahlen",
      "prompt": "Welche dieser Zahlen sind Primzahlen?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Mathe",
      "adminNotes": "Mehrfachauswahl",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 20, "wrongPoints": -5},
      "options": [
        {"id": "a", "label": "2"},
        {"id": "b", "label": "9"},
        {"id": "c", "label": "13"},
        {"id": "d", "label": "21"}
      ],
      "correctOptionId": null,
      "correctOptionIds": ["a", "c"],
      "allowMultipleAnswers": true
    },
    {
      "type": "buzzer",
      "id": "q-gold",
      "prompt": "Welches chemische Element hat das Symbol „Au“?",
      "timeLimitMs": 20000,
      "softTimeLimit": false,
      "category": "Chemie",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "firstBuzzer", "points": 15, "penalty": -5, "rankDecay": 5},
      "expectedAnswer": "Gold",
      "lockOutOnMiss": true,
      "hostEndsRound": false,
      "retryLimit": null
    },
    {
      "type": "shortAnswer",
      "id": "q-planet",
      "prompt": "Wie heißt der größte Planet unseres Sonnensystems?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Astronomie",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "acceptedAnswers": ["Jupiter"],
      "maxEdits": 1,
      "manualGrading": false
    },
    {
      "type": "ordering",
      "id": "q-reihenfolge",
      "prompt": "Sortiere die Erfindungen von alt nach neu.",
      "timeLimitMs": 40000,
      "softTimeLimit": false,
      "category": "Geschichte",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 15, "wrongPoints": 0},
      "items": [
        {"id": "telefon", "label": "Telefon"},
        {"id": "buchdruck", "label": "Buchdruck"},
        {"id": "internet", "label": "Internet"}
      ],
      "correctOrder": ["buchdruck", "telefon", "internet"]
    },
    {
      "type": "matching",
      "id": "q-zuordnung",
      "prompt": "Ordne die Komponisten ihren Werken zu.",
      "timeLimitMs": 45000,
      "softTimeLimit": false,
      "category": "Musik",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 15, "wrongPoints": 0},
      "leftItems": [
        {"id": "mozart", "label": "Mozart"},
        {"id": "beethoven", "label": "Beethoven"}
      ],
      "rightItems": [
        {"id": "zauberfloete", "label": "Die Zauberflöte"},
        {"id": "neunte", "label": "9. Sinfonie"}
      ],
      "correctPairs": {"mozart": "zauberfloete", "beethoven": "neunte"}
    },
    {
      "type": "estimation",
      "id": "q-schaetzen",
      "prompt": "Wie hoch ist der Eiffelturm (mit Antennen)?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Bauwerke",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 20, "wrongPoints": 0},
      "correctValue": 330,
      "zeroScale": 1,
      "unit": "m"
    },
    {
      "type": "trueFalse",
      "id": "q-wahrfalsch",
      "prompt": "Dieser Code gibt 4 aus.",
      "timeLimitMs": 20000,
      "softTimeLimit": false,
      "category": "Technik",
      "adminNotes": "",
      "media": [
        {"type": "code", "caption": "", "hideDetails": false, "code": "print(2 + 2);", "language": "dart"}
      ],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": true
    }
  ],
  "teams": [],
  "format": {"type": "standard", "revealMode": "afterEachQuestion"},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Jeopardy (zwei Teams, Daily Double)

```json quizmo-example
{
  "schemaVersion": 7,
  "id": "quiz-ki-jeopardy-beispiel",
  "name": "Jeopardy: Natur & Technik",
  "description": "Kleines Board mit zwei Kategorien.",
  "category": "Jeopardy",
  "questions": [
    {
      "type": "shortAnswer", "id": "n1", "prompt": "Wie viele Beine hat eine Spinne?",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": "Natur", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "acceptedAnswers": ["8", "acht"], "maxEdits": 0, "manualGrading": false
    },
    {
      "type": "trueFalse", "id": "n2", "prompt": "Wale sind Fische.",
      "timeLimitMs": 15000, "softTimeLimit": false, "category": "Natur", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": false
    },
    {
      "type": "buzzer", "id": "t1", "prompt": "Wer gilt als Erfinder des World Wide Web?",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": "Technik", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "firstBuzzer", "points": 10, "penalty": 0, "rankDecay": 0},
      "expectedAnswer": "Tim Berners-Lee", "lockOutOnMiss": true, "hostEndsRound": false, "retryLimit": null
    },
    {
      "type": "multipleChoice", "id": "t2", "prompt": "Wofür steht „CPU“?",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": "Technik", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Central Processing Unit"},
        {"id": "b", "label": "Computer Power Unit"}
      ],
      "correctOptionId": "a", "correctOptionIds": null, "allowMultipleAnswers": false
    }
  ],
  "teams": [
    {"id": "team-rot", "name": "Rot", "colorValue": 4293212469},
    {"id": "team-blau", "name": "Blau", "colorValue": 4280191205}
  ],
  "format": {
    "type": "jeopardy",
    "board": {
      "categories": [
        {"name": "Natur", "cells": [
          {"questionId": "n1", "dailyDouble": false},
          {"questionId": "n2", "dailyDouble": true}
        ]},
        {"name": "Technik", "cells": [
          {"questionId": "t1", "dailyDouble": false},
          {"questionId": "t2", "dailyDouble": false}
        ]}
      ],
      "rowPoints": [100, 200],
      "penalizeWrongAnswers": false,
      "allowSteal": true
    }
  },
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Pokerchips (Teams entstehen beim Beitritt)

```json quizmo-example
{
  "schemaVersion": 7,
  "id": "quiz-ki-poker-beispiel",
  "name": "Pokerchips: Wie sicher bist du?",
  "description": "Teams setzen Chips auf ihr Wissen.",
  "category": "Poker",
  "questions": [
    {
      "type": "estimation", "id": "p1", "prompt": "In welchem Jahr fiel die Berliner Mauer?",
      "timeLimitMs": 30000, "softTimeLimit": false, "category": "Geschichte", "adminNotes": "Poker zahlt nur bei exakt richtiger Antwort aus.",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctValue": 1989, "zeroScale": 1, "unit": ""
    },
    {
      "type": "multipleChoice", "id": "p2", "prompt": "Welches ist das größte Organ des Menschen?",
      "timeLimitMs": 25000, "softTimeLimit": false, "category": "Biologie", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Leber"},
        {"id": "b", "label": "Haut"},
        {"id": "c", "label": "Lunge"}
      ],
      "correctOptionId": "b", "correctOptionIds": null, "allowMultipleAnswers": false
    }
  ],
  "teams": [],
  "format": {"type": "poker", "startingChips": 100},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```
