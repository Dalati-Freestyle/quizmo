# Quizmo-Quiz mit einem KI-Assistenten erstellen

<!--
  Diese Datei ist gleichzeitig die Anleitung im Repository und die Datei, die
  Quizmo unter Einstellungen → „Quiz mit KI erstellen“ ausliefert (Asset).
  Die englische Fassung ist ai-quiz-guide.en.md; beide stets gemeinsam pflegen.
  test/core/data/ai_quiz_guide_test.dart importiert jedes Beispiel unten und
  schlägt fehl, sobald sich die schemaVersion ändert. Dann diese Anleitung an
  das neue Schema anpassen.
-->

Quizmo-Schema-Version dieser Anleitung: **15**

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

* Stelle höchstens die nötigsten Rückfragen: das Thema, ggf. Sprache oder
  Zielgruppe (falls nicht erkennbar) **und immer die Zeitlimits** (siehe
  „Zeitlimits“ unten), sofern die Person sie nicht schon genannt hat.
* Entscheide alles andere selbst: Format, Teams oder Solo, Wertung, Anzahl und
  Art der Fragen (gemischt, mindestens drei verschiedene Fragetypen).
* Gib danach sofort die fertige Datei aus.

### Zeitlimits – immer nachfragen

Lege Zeitlimits **nie eigenmächtig** fest; zu knappe Limits verderben das
Spiel. Hat die Person nichts dazu gesagt, frage in jedem Modus nach – in einer
einzigen Frage:

> „Sollen die Fragen ein Zeitlimit haben? Wenn ja: wie viele Sekunden, und soll
> es **hart** sein (Antworten schließen automatisch, wenn die Zeit abläuft) oder
> **weich** (die Uhr läuft nur als Orientierung, die Spielleitung beendet die
> Runde selbst)?“

* Ohne Zeitlimit: `"timeLimitMs": 0`. Hart: `"softTimeLimit": false`, weich:
  `"softTimeLimit": true` (jeweils mit `timeLimitMs` > 0).
* Überlässt die Person es dir, wähle großzügig: lieber kein Limit oder
  mindestens 45 Sekunden; Fragen mit Video, Audio, langen Texten oder
  Rechnungen deutlich mehr. Ein Geschwindigkeitsbonus braucht ein Limit.
* Gilt ein Limit für das ganze Quiz, nenne die Ausnahmen pro Frage.

### Geführter Modus

Kläre **zuerst alles, was sich durch das ganze Quiz zieht**, bevor die erste
Frage entsteht. Frage aktiv nach und schlage sinnvolle Standards vor:

1. **Quizformat** – Standard, Jeopardy, Pokerchips oder Biggest Snowflake
   (siehe Abschnitt 3) samt formatspezifischer Regeln (Board-Aufbau,
   Minuspunkte, Steal, Startchips, Auflösung nach jeder Frage oder am Ende,
   Snowflake-Wertung).
2. **Teams oder Solo** – vordefinierte Teams (Namen, Farben) oder Einzelspieler.
3. **Zeitlimits** – immer fragen (siehe „Zeitlimits“ oben): kein Zeitlimit
   (Spielleitung beendet die Runde) oder eine Standard-Zeit pro Frage, und ob
   das Limit hart oder weich ist.
4. **Bilder und Medien** – ob Bilder (oder Audio/Video) zu Fragen oder Lösungen
   gehören sollen; die Person kann sie dir im Chat schicken (siehe Abschnitt 6).
5. **Wertung** – feste Punkte, Geschwindigkeitsbonus, Buzzer-Wertung,
   Minuspunkte bei falscher Antwort.
6. **Inhalt** – Thema, Zielgruppe, Schwierigkeit, Sprache, Anzahl der Fragen
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
   Eingebettete Bilder, Audio und Videos stecken in der Datei und kommen beim
   Import mit. Was du nicht einbetten konntest, lädt die Person danach im
   Quiz-Editor bei der jeweiligen Frage (oder Lösung) über „Medien“ hoch.

## 2. Aufbau der Datei

```text
{
  "schemaVersion": 15,              // immer genau 15
  "id": "quiz-…",                   // eindeutige ID, nur a-z, 0-9 und -
  "name": "Titel",
  "description": "Kurze Beschreibung (nicht leer)",
  "category": "Kategorie (nicht leer)",
  "questions": [ … ],               // siehe Abschnitt 4
  "teams": [ … ],                   // leer = Solo (bei Poker: Teams entstehen beim Beitritt)
  "format": { … },                  // siehe Abschnitt 3
  "jokers": [ … ],                  // optional, siehe „Joker“; leer = keine Joker
  "slides": [ … ],                  // optional, Zwischenfolien, siehe unten
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

* `createdAtMicros` / `updatedAtMicros`: Zeitpunkt in Mikrosekunden seit
  1970 (UTC). Nimm den aktuellen Zeitpunkt; `updatedAtMicros` darf nicht vor
  `createdAtMicros` liegen.
* Team: `{"id": "team-rot", "name": "Rot", "color": "red"}` – `color` ist der
  Name einer Farbe der Quizmo-Palette (dieselben Farben wie in der
  Admin-Ansicht). Erlaubt sind genau diese Namen: `blue` (Blau), `teal`
  (Türkis), `orange`, `purple` (Lila), `green` (Grün), `pink`, `ochre` (Ocker),
  `cyan`, `red` (Rot), `olive` (Oliv), `indigo`, `brown` (Braun), `darkTeal`
  (Petrol), `orchid` (Orchidee), `slate` (Schiefergrau), `vermilion` (Zinnober).
  Niemals Farbcodes (Hex, ARGB) verwenden. Gib jedem Team eine andere Farbe.
* Alle IDs (Quiz, Teams, Fragen, Optionen) sind innerhalb ihrer Liste eindeutig.

## 3. Quizformate

| Format | `format` | Hinweise |
| --- | --- | --- |
| Standard | `{"type": "standard", "revealMode": "afterEachQuestion"}` | Fragen der Reihe nach. `revealMode`: `afterEachQuestion` (Lösung nach jeder Frage) oder `atEnd` (alle Lösungen und Punkte erst am Ende). |
| Jeopardy | `{"type": "jeopardy", "board": { … }}` | Board aus Kategorien (Spalten) × Zeilen. Punkte kommen aus der Zeile, nicht aus der Frage. |
| Pokerchips | `{"type": "poker", "startingChips": 100, "minStake": 0, "maxStake": 50}` | Teams setzen vor jeder Frage Chips (1–1.000.000 Startchips). Richtig = doppelter Einsatz zurück, falsch = Einsatz weg. Optional: `minStake` (Mindesteinsatz, Standard 0 = Aussetzen erlaubt; wer weniger Chips hat, geht all-in) und `maxStake` (Höchsteinsatz, weglassen = kein Limit). `teams` darf leer sein. |

| Biggest Snowflake | `{"type": "snowflake", "scoring": "winnerOnly"}` | Es gibt **keine richtige Lösung**: Punkte bekommt, wer die Antwort gibt, die am wenigsten Spieler gewählt haben. `scoring`: `winnerOnly` (nur die seltenste Antwort punktet) oder `graded` (der Anteil sinkt mit jeder Stufe häufigerer Antworten, die häufigste bekommt nichts). Details unten. |

**Joker** (`jokers`, optional): Ein Quiz hat nur dann Joker, wenn sie hier
stehen. Jede Art höchstens einmal; `usesPerTeam` sagt, wie oft jedes Team sie
spielen darf (1–99). Ein Team kann pro Frage nur von einem Joker betroffen
sein. Beide Joker gibt es nur im Format Pokerchips und werden in der
Einsatzphase gespielt:

| Joker | Eintrag | Wirkung |
| --- | --- | --- |
| Kredit (defensiv) | `{"type": "credit", "usesPerTeam": 1, "maxLoss": 1}` | Geht der Einsatz verloren, verliert das Team nur `maxLoss` Chips davon. |
| 50/50 Chance (Angriff) | `{"type": "forcedStake", "usesPerTeam": 1, "stake": 3, "cost": 2, "lossFactor": 2}` | Zwingt ein anderes Team, `stake` Chips zu setzen (all-in, wenn es weniger hat). Richtig = übliche Auszahlung, falsch = `lossFactor` × Einsatz weg. Kostet den Angreifer `cost` Chips. |

Ist ein Joker dabei, der **vor dem Aufdecken** gespielt wird (`forcedStake`),
beginnt jede Poker-Frage mit einer Kategorie-Phase: Spieler und TV sehen nur
das Feld `category` der Frage, Angriffs-Joker werden gespielt, dann deckt der
Spielleiter die Frage auf; danach Kredit-Joker und Einsätze, dann Antworten.
Gib Poker-Fragen deshalb eine aussagekräftige `category`.

**Zwischenfolien** (`slides`, optional): Bildschirme ohne Wertung zwischen den
Fragen (Pause, Kategorie-Titel, „Das Ergebnis ist unterwegs“), in jedem Format.
`{"id": "folie-pause", "title": "Trinkpause", "text": "", "media": [],
"beforeQuestionId": "q3"}` – `beforeQuestionId` ist die ID der Frage, vor der
die Folie steht, weglassen = nach der letzten Frage. Titel, Text oder ein
Medium ist Pflicht; `media` wie bei Fragen (höchstens zehn).

**Biggest Snowflake:**

* Erlaubt sind nur die Fragetypen `multipleChoice`, `trueFalse`, `ordering` und
  `matching`. `buzzer`, `shortAnswer` und `estimation` sind nicht möglich.
* Die Fragen speichern **keine Lösung**: setze `correctOptionId`,
  `correctOptionIds`, `correctAnswer`, `correctOrder` und `correctPairs` auf
  `null`. Schreibe Fragen, bei denen es um Meinungen, Vorlieben oder
  Einschätzungen geht, nicht um Wissen.
* Die Punkte kommen aus der `scoringRule` der Frage (am besten `fixed`); sie
  werden mit dem Anteil multipliziert. Gleich seltene Antworten teilen sich
  eine Stufe. Geben alle dieselbe Antwort, punktet niemand.
* Gezählt wird pro Spieler; `teams` darf leer sein.

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
* Jeder Fragetyp funktioniert in jedem Format; einzige Ausnahme ist Biggest
  Snowflake (siehe oben).

## 4. Gemeinsame Felder jeder Frage

```text
{
  "type": "…",                  // siehe Abschnitt 5
  "id": "q1",                   // eindeutig
  "prompt": "Fragetext",
  "timeLimitMs": 30000,         // in Millisekunden; 0 = kein Zeitlimit (Spielleitung beendet die Runde)
  "softTimeLimit": false,       // true = Runde bleibt nach Ablauf offen, bis die Spielleitung beendet
  "category": "Geschichte",     // optional, sonst null
  "adminNotes": "",             // Notiz nur für die Spielleitung
  "media": [],                  // Anhänge zur Frage (Abschnitt 6)
  "solutionMedia": [],          // Anhänge, die erst mit der Lösung erscheinen
  "hints": [],                  // optional, Tipps (siehe unten)
  "scoringRule": { … }          // Wertung, siehe unten
}
```

**Wertung (`scoringRule`):**

| Regel | JSON | Bedeutung |
| --- | --- | --- |
| Feste Punkte | `{"type": "fixed", "correctPoints": 10, "wrongPoints": 0}` | Richtig = `correctPoints`; falsch = `wrongPoints` (0 oder negativ). |
| Geschwindigkeitsbonus | `{"type": "speedBonus", "basePoints": 10, "maxSpeedBonus": 10, "wrongPoints": 0}` | Grundpunkte plus Bonus, je schneller die Antwort. Braucht ein Zeitlimit (`timeLimitMs` > 0). |
| Buzzer | `{"type": "firstBuzzer", "points": 15, "penalty": -5, "rankDecay": 5}` | Für Buzzerfragen: Punkte für richtig, `penalty` für falsch, `rankDecay` Abzug pro späterem Rang. |

Bei Schätzfragen werden die Punkte anteilig nach Genauigkeit vergeben. Auf einem
Jeopardy-Board und im Pokerformat ersetzt das Format die Punkte; gib trotzdem
eine gültige `scoringRule` an (z. B. `fixed` mit 10/0).

**Tipps (`hints`, optional):** Liste von höchstens 10 Tipps, die die
Spielleitung während der Frage von oben nach unten einzeln aufdeckt:

```text
"hints": [
  {"text": "Es ist nicht die größte Stadt.", "media": [], "cost": 0},
  {"text": "Sie beginnt mit C.", "media": [], "cost": 3}
]
```

Jeder Tipp braucht `text` oder `media` (wie in Abschnitt 6, höchstens 10).
`cost` ist der Punktabzug (ganze Zahl ≥ 0; 0 = kostenlos): Wer erst nach dem
Tipp richtig antwortet, erhält so viele Punkte weniger, nie weniger als 0.
Falsche Antworten bleiben unverändert. Auf einem Jeopardy-Board zählt der Abzug
gegen die Punkte der Zeile bzw. den Daily-Double-Einsatz, wähle ihn passend; im
Pokerformat sind Tipps immer kostenlos. Ordne Tipps von vage nach deutlich, und
nimm nie die Lösung selbst als Tipp.

**Formatierung (Markdown):** `prompt`, `adminNotes`, der `text` von Tipps und von
Folien dürfen Markdown enthalten: `**fett**`, `*kursiv*`, `~~durchgestrichen~~`,
Überschriften `#` bis `###`, Listen (`- Punkt`, `1. Punkt`), Zitate (`> Text`),
`` `Code` `` und Codeblöcke, Trennlinien (`---`) und Links `[Text](https://…)`.
Ein einfacher Zeilenumbruch bleibt sichtbar. HTML, Bilder und Tabellen werden
nicht umgewandelt (Bilder gehören in `media`). Soll ein Zeichen wie `*` als
Zeichen erscheinen, schreibe `\*`. Alle anderen Felder (Antworten, Lösungen,
Titel, Kategorien) sind reiner Text.

## 5. Fragetypen

| `type` | Zusätzliche Felder | Regeln |
| --- | --- | --- |
| `multipleChoice` | `options` (Liste `{"id","label"}`), `correctOptionId`, `correctOptionIds`, `allowMultipleAnswers` | Mindestens 2 Optionen. Einfachauswahl: `correctOptionId` = ID, `correctOptionIds` = `null`, `allowMultipleAnswers` = `false`. Mehrfachauswahl: `correctOptionId` = `null`, `correctOptionIds` = Liste, `allowMultipleAnswers` = `true`. |
| `buzzer` | `expectedAnswer`, `lockOutOnMiss`, `hostEndsRound`, `retryLimit` | Wer zuerst buzzert, antwortet mündlich; die Spielleitung bewertet. `retryLimit`: `null` = unbegrenzt, sonst ≥ 0. Wertung meist `firstBuzzer`. |
| `shortAnswer` | `acceptedAnswers` (Liste), `maxEdits` (0–5), `manualGrading` | Freitext. Mindestens eine akzeptierte Antwort. `maxEdits` = erlaubte Tippfehler. `manualGrading: true` = Spielleitung bewertet von Hand. |
| `ordering` | `items` (Liste `{"id","label"}`), `correctOrder` (Liste der IDs) | Reihenfolge. Mindestens 2 Elemente; `correctOrder` enthält jede ID genau einmal. |
| `matching` | `leftItems`, `rightItems` (je Liste `{"id","label"}`), `correctPairs` (`{"linkeId": "rechteId"}`) | Zuordnung. Gleich viele Elemente links und rechts; jede linke ID genau einer eigenen rechten ID zuordnen. Passt ein Wert zu mehreren linken Elementen (z. B. zwei Gerichte mit Schwein), lege ihn rechts mehrfach mit gleichem `label` und verschiedenen IDs an: gleiche Werte sind untereinander austauschbar. |
| `estimation` | `correctValue` (Zahl), `zeroScale` (> 0), `unit`, optional `minAccepted` und `maxAccepted` | Schätzfrage. Punkte anteilig `max(0, 1 − |Antwort − Ziel| / |Ziel|)`; bei Ziel 0 ersetzt `zeroScale` den Nenner. Mit `minAccepted`/`maxAccepted` (immer beide, Ziel dazwischen, Grenzen zählen mit) gilt jede Antwort im Bereich als vollständig richtig. Im Pokerformat immer angeben, denn dort zahlt nur eine vollständig richtige Antwort aus. |
| `trueFalse` | `correctAnswer` (`true`/`false`) | Wahr/Falsch. |

## 6. Medien

Bilder, Audio und Videos können **direkt in die Datei eingebettet** werden; sie
reisen beim Export und Import mit (eine einzige `.quizmo.json`, keine
Größengrenze seit Schema 11). `media` erscheint mit der Frage, `solutionMedia`
erst mit der Lösung – frage, wohin ein Bild gehört (Bild zur Frage, Auflösung).

**Eingebettete Datei:** `asset.id` ist der SHA-256-Hash (64 Kleinbuchstaben, hex)
der Datei-Bytes, `asset.data` ist die Base64-Kodierung derselben Bytes,
`mimeType` muss zum Inhalt passen. Quizmo prüft das beim Import und lehnt die
**ganze Datei** ab, wenn Hash, Daten oder Format nicht stimmen.

* Bette nur Dateien ein, deren Bytes du wirklich hast: Bilder, die die Person
  dir im Chat schickt, oder die du mit einem Werkzeug erzeugst. Berechne Hash
  und Base64 dann **mit Code** (Code-Ausführung, z. B. Python, Skript unten) –
  niemals schätzen, abtippen oder erfinden.
* Kannst du keinen Code ausführen, bette nichts ein: Lass die Anhänge leer,
  schreibe in `adminNotes`, welches Bild wohin gehört, und weise darauf hin,
  dass die Person es nach dem Import im Quiz-Editor über „Medien“ hochlädt.
* Erlaubt: PNG, JPEG, WebP, SVG (ohne Skripte), MP3, WAV, OGG, MP4. Bilder
  möglichst klein halten (z. B. höchstens 1920 px breit, JPEG), sonst wird die
  Datei sehr groß.

| Art | JSON |
| --- | --- |
| Bild | `{"type": "image", "caption": "", "hideDetails": false, "zoom": true, "asset": {"id": "<sha256>", "mimeType": "image/png", "data": "<base64>"}}` – `zoom`: Bild per Tipp vergrößerbar. |
| Audio | `{"type": "audio", "caption": "", "hideDetails": false, "playbackLimitSeconds": null, "softPlaybackLimit": false, "asset": {"id": "<sha256>", "mimeType": "audio/mpeg", "data": "<base64>"}}` |
| Video (MP4) | `{"type": "video", "caption": "", "hideDetails": false, "youtubeId": null, "asset": {"id": "<sha256>", "mimeType": "video/mp4", "data": "<base64>"}}` |

Skript, das aus einer Datei den fertigen Eintrag erzeugt:

```python
import base64, hashlib, json, pathlib

def medium(path, kind="image", caption=""):
    data = pathlib.Path(path).read_bytes()
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
            ".webp": "image/webp", ".svg": "image/svg+xml", ".mp3": "audio/mpeg",
            ".wav": "audio/wav", ".ogg": "audio/ogg", ".mp4": "video/mp4"}[pathlib.Path(path).suffix.lower()]
    entry = {"type": kind, "caption": caption, "hideDetails": False,
             "asset": {"id": hashlib.sha256(data).hexdigest(), "mimeType": mime,
                       "data": base64.b64encode(data).decode()}}
    if kind == "image": entry["zoom"] = True
    if kind == "audio": entry |= {"playbackLimitSeconds": None, "softPlaybackLimit": False}
    if kind == "video": entry["youtubeId"] = None
    return entry

print(json.dumps(medium("bild.png")))
```

Ohne Datei-Inhalt gehen außerdem diese Verweise:

| Art | JSON |
| --- | --- |
| YouTube-Video | `{"type": "video", "caption": "", "hideDetails": false, "asset": null, "youtubeId": "aqz-KE-bpKQ"}` – nur die Video-ID; nur echte, existierende Videos verwenden. Braucht Internet. |
| Kartenausschnitt | `{"type": "geo", "caption": "Berlin", "hideDetails": false, "latitude": 52.52, "longitude": 13.405, "zoom": 10.0}` – OpenStreetMap, braucht Internet. |
| Code/Text | `{"type": "code", "caption": "", "hideDetails": false, "code": "print(1 + 1);", "language": "dart"}` – Syntaxhervorhebung; `language` z. B. `dart`, `python`, `javascript`, `text`. |

`hideDetails: true` verbirgt Beschriftung/Titel auf Spieler- und TV-Geräten.
Höchstens 10 Anhänge pro Frage (Frage und Lösung zusammen).

## 7. Checkliste vor der Ausgabe

- [ ] `"schemaVersion": 15` steht ganz oben.
- [ ] `name`, `description` und `category` sind nicht leer.
- [ ] Alle IDs sind eindeutig und nicht leer.
- [ ] Jede Frage hat einen Text, ein Zeitlimit ≥ 0 (0 = keins; ein
      Geschwindigkeitsbonus braucht > 0) und eine gültige `scoringRule`.
- [ ] Jede Frage hat eine vollständige, gültige Lösung (siehe Abschnitt 5) –
      außer bei Biggest Snowflake: dort sind alle Lösungsfelder `null`.
- [ ] Biggest Snowflake: nur `multipleChoice`, `trueFalse`, `ordering` und
      `matching`; `scoring` ist `winnerOnly` oder `graded`.
- [ ] Jeopardy: Jede `questionId` existiert, keine Frage doppelt, Zeilenpunkte > 0,
      jede Kategorie hat einen Namen, mindestens zwei Teams.
- [ ] Joker nur im Format Pokerchips, jede Art höchstens einmal.
- [ ] Poker: `startingChips` zwischen 1 und 1.000.000; `minStake` zwischen 0 und `startingChips`; `maxStake` (falls angegeben) zwischen `minStake` (mindestens 1) und `startingChips`.
- [ ] Teams haben `id`, `name` und `color` (ein Palettenname aus Abschnitt 2).
- [ ] Eingebettete Medien nur mit echten Bytes: `id` = SHA-256 von genau
      diesen Bytes, `data` = Base64, `mimeType` passend – mit Code berechnet.
      Sonst Anhang weglassen und in `adminNotes` vermerken.
- [ ] Zeitlimits hat die Person festgelegt (oder ausdrücklich dir überlassen);
      hart/weich (`softTimeLimit`) entspricht ihrer Antwort.
- [ ] Gültiges JSON: doppelte Anführungszeichen, keine Kommentare, keine
      nachgestellten Kommas.

## 8. Vollständige Beispiele

Die folgenden Dateien sind gültig und lassen sich unverändert importieren.

### Standard (Solo, alle Fragetypen)

```json quizmo-example
{
  "schemaVersion": 15,
  "id": "quiz-ki-standard-beispiel",
  "name": "Allgemeinwissen kompakt",
  "description": "Acht Fragen mit allen Fragetypen.",
  "category": "Allgemeinwissen",
  "questions": [
    {
      "type": "multipleChoice",
      "id": "q-hauptstadt",
      "prompt": "**Welche Stadt ist die Hauptstadt von Kanada**?",
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
      "hints": [
        {"text": "Eine Primzahl ist nur durch 1 und sich selbst teilbar.", "media": [], "cost": 2}
      ],
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
      "correctValue": 330, "minAccepted": 320, "maxAccepted": 340,
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
      "solutionMedia": [
        {"type": "image", "caption": "Bild zur Lösung", "hideDetails": false, "zoom": true, "asset": {"id": "6eac1db9594fa41f49be880b8dd3fa9d0a2c81361a6b2ee54896688adfb9fbbf", "mimeType": "image/svg+xml", "data": "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMjAgODAiPjxyZWN0IHdpZHRoPSIxMjAiIGhlaWdodD0iODAiIGZpbGw9IiMxZTg4ZTUiLz48Y2lyY2xlIGN4PSI2MCIgY3k9IjQwIiByPSIyNCIgZmlsbD0iI2ZmZWIzYiIvPjwvc3ZnPg=="}}
      ],
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
  "schemaVersion": 15,
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
      "timeLimitMs": 0, "softTimeLimit": false, "category": "Technik", "adminNotes": "",
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
    {"id": "team-rot", "name": "Rot", "color": "red"},
    {"id": "team-blau", "name": "Blau", "color": "blue"}
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
  "schemaVersion": 15,
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
  "format": {"type": "poker", "startingChips": 100, "minStake": 5, "maxStake": 50},
  "jokers": [
    {"type": "credit", "usesPerTeam": 1, "maxLoss": 1},
    {"type": "forcedStake", "usesPerTeam": 1, "stake": 30, "cost": 10, "lossFactor": 2}
  ],
  "slides": [
    {"id": "folie-start", "title": "Willkommen!", "text": "Gleich geht es los.", "media": [], "beforeQuestionId": "p1"},
    {"id": "folie-ende", "title": "Das Ergebnis ist unterwegs!", "text": "", "media": []}
  ],
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Biggest Snowflake (die seltenste Antwort gewinnt)

```json quizmo-example
{
  "schemaVersion": 15,
  "id": "quiz-ki-snowflake-beispiel",
  "name": "Biggest Snowflake: Wer tickt anders?",
  "description": "Keine richtige Lösung: Es punktet, wer anders antwortet als die Mehrheit.",
  "category": "Party",
  "questions": [
    {
      "type": "trueFalse", "id": "s1", "prompt": "Ananas gehört auf Pizza.",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": null
    },
    {
      "type": "multipleChoice", "id": "s2", "prompt": "Welche Jahreszeit ist die beste?",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Frühling"},
        {"id": "b", "label": "Sommer"},
        {"id": "c", "label": "Herbst"},
        {"id": "d", "label": "Winter"}
      ],
      "correctOptionId": null, "correctOptionIds": null, "allowMultipleAnswers": false
    },
    {
      "type": "ordering", "id": "s3", "prompt": "Sortiere von „am wichtigsten“ nach „am unwichtigsten“.",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "items": [
        {"id": "a", "label": "Schlaf"},
        {"id": "b", "label": "Essen"},
        {"id": "c", "label": "WLAN"}
      ],
      "correctOrder": null
    },
    {
      "type": "matching", "id": "s4", "prompt": "Welches Getränk passt zu welcher Tageszeit?",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "leftItems": [
        {"id": "l1", "label": "Morgens"},
        {"id": "l2", "label": "Abends"}
      ],
      "rightItems": [
        {"id": "r1", "label": "Kaffee"},
        {"id": "r2", "label": "Tee"}
      ],
      "correctPairs": null
    }
  ],
  "teams": [],
  "format": {"type": "snowflake", "scoring": "graded"},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```
