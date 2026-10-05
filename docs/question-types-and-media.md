# Fragetypen und Medien

Im Quiz-Editor bietet „Neuer Fragetyp“ alle Varianten an. In Jeopardy sind
dieselben Vorlagen beim Bearbeiten einer Zelle verfügbar.

| Typ | Lösung und Auswertung |
| --- | --- |
| Freitext | Akzeptierte Antworten, eine pro Zeile. Groß-/Kleinschreibung und mehrfache Leerzeichen werden normalisiert. 0–5 Zeichenänderungen (Levenshtein-Distanz) sind einstellbar. |
| Reihenfolge | Elemente in der richtigen Reihenfolge eingeben. Spieler sortieren mit Hoch-/Runter-Buttons. Nur eine vollständige korrekte Reihenfolge zählt. |
| Zuordnung | Je Zeile `links = rechts`. Spieler wählen für jedes linke Element einen eindeutigen Partner. Nur die vollständige korrekte Zuordnung zählt. |
| Schätzfrage | Endliche Zielzahl und optionale Einheit. Anteil der Maximalpunkte: `max(0, 1 - abs(Antwort - Ziel) / abs(Ziel))`. Bei Ziel 0 ersetzt die einstellbare Null-Skala den Nenner. Ganze Punkte werden gerundet. |
| Wahr/Falsch | Binäre Lösung und Auswahl. |

Die bestehende Punkte-Regel bestimmt die Maximalpunkte. Auf einem Jeopardy-Board
werden stattdessen die Zeilenpunkte bzw. der Daily-Double-Einsatz verwendet.
Zeitlimits, Team-Regeln, Steals und Uhrensynchronisation gelten weiterhin.

Jede Frage hat `media` und `solutionMedia`. Lösungsmedien und Lösungen werden erst
bei der Auflösung veröffentlicht. Unterstützt sind PNG/JPEG/WebP/SVG mit Zoom,
MP3/WAV/OGG mit Play/Pause und optionalem Abspiellimit, MP4 mit Play/Pause und
Positionssteuerung, YouTube-Links, Code mit Syntaxhervorhebung sowie verschiebbare
OpenStreetMap-Kartenausschnitte. Medien werden im Editor vorab angezeigt.
YouTube und Kartenkacheln benötigen Internet; lokale Uploads funktionieren im LAN.
Mit „Details ausblenden“ bleiben Beschriftungen und Dateinamen auf Spieler- und
TV-Ansichten verborgen und werden auch aus den übertragenen Snapshots entfernt.
YouTube kann eigene Titel einblenden; MP4-Uploads zeigen keine solchen Titel.
Die TV-Ansicht startet Audio und Videos automatisch. Der Host kann die Wiedergabe
im Panel „TV-Medienwiedergabe“ abspielen, pausieren und neu starten. Browser können
Autoplay mit Ton bis zu einer lokalen Interaktion sperren; die lokalen Play-Buttons
bleiben dafür verfügbar. Lösungsmedien starten erst nach dem Reveal.
Codec-Unterstützung hängt vom Browser bzw. Betriebssystem ab. Die nativen
Audio-/Video-Plugins unterstützen Android, iOS und macOS; Web ist ebenfalls
unterstützt. YouTube öffnet auf Windows/Linux extern.

## Speicherung und HTTP

Quizmo verwendet versionierte JSON-Dokumente, keine SQL-Datenbank. Schema-Version
1 bleibt lesbar; neue Typ-Tags sind `shortAnswer`, `ordering`, `matching`,
`estimation` und `trueFalse`. Bestehende Fragen ohne Medienlisten laden mit leeren
Listen. Lösungen bleiben separate nullable Felder: `acceptedAnswers`,
`correctOrder`, `correctPairs`, `correctValue`, `correctAnswer`.

Uploads werden als Base64 mit SHA-256-ID und MIME-Typ in der Quizdatei gespeichert.
So reisen Dateien beim Export/Import mit. Grenze: 20 MiB pro Datei, zehn Anhänge
pro Frage, 90 MiB kodierte Medien pro Quiz und 100 MiB pro importierter Quizdatei.
Beschädigte Dateien, MIME-Spoofing und SVG mit aktiven Inhalten oder externen
Referenzen werden abgewiesen. SVG-Unterstützung beschränkt sich auf passive,
selbst enthaltene Grafiken ohne Stylesheets, eingebettete Bilder oder Animation.

Spieler-Snapshots enthalten nur Asset-Metadaten. `GET`/`HEAD /api/media/<sha256>`
liefert nur sichtbare Anhänge der laufenden Frage mit festen MIME-Typen,
`nosniff`, `no-store` und Unterstützung einzelner Byte-Bereiche (206/416).
Uploads erfolgen ausschließlich lokal im Host-Editor; das LAN bietet keinen
öffentlichen Upload-Endpunkt. Native Vorschauen verwenden temporäre Dateien,
die nach dem Schließen des Players gelöscht werden.

Nach Änderungen: `flutter test`, `dart analyze`,
`dart run tool/bundle_web_client.dart`, danach die Host-App neu bauen.

## Jeopardy-Auswahl

Das Team am Zug wählt die nächste Frage direkt auf seinem Spielergerät. Nach dem
Reveal wird darunter erneut das Board angezeigt. Der Host kann den aktuellen Zug
weiterhin überschreiben und über „Team-Reihenfolge festlegen“ die Rotation für die
laufende Sitzung ändern. Ein Reset behält die Reihenfolge bei und beginnt mit
deren erstem Team. Neu hinzukommende Teams werden an die Reihenfolge angehängt.
Ein ausgewähltes Daily Double wartet auf den Einsatz des auswählenden Teams; der
Host kann den Einsatz alternativ im Board-Panel eingeben. Währenddessen bleiben
Feld und Team am Zug fest. Gespielte Felder behalten ihre durchgestrichenen
Punktwerte und zeigen das Team bzw. den Spieler, das/der Punkte gewonnen hat.
