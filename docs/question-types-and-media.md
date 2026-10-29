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
Vor dem Einlesen prüft der Editor die Dateigröße anhand der Picker-Metadaten.
Leere Dateien, unbekannte Größen und Dateien über 20 MiB werden verständlich
abgewiesen; Dateiendung und tatsächlicher Inhalt werden anschließend geprüft.
Rasterbilder müssen außerdem vom Bilddecoder der aktuellen Plattform lesbar sein.
MP4 bezeichnet einen Container und garantiert keinen unterstützten Codec.
H.264 mit AAC sowie MP3 sind meist die kompatibelste Wahl. Die Wiedergabe muss
auf den vorgesehenen Spieler- und TV-Geräten ausprobiert werden.

Bei Rasterbildern bleibt das Original die Voreinstellung. Optional erzeugt
„Optimierte PNG-Kopie als Vorschau“ eine verkleinerte, seitenverhältnistreue
Kopie (maximale Kantenlänge 3840/2560/1920/1280 Pixel, kein Hochskalieren).
Die Vorschau zeigt beide Bilder, Abmessungen und Dateigrößen. Nur die ausdrückliche
Auswahl „Optimierte Kopie verwenden“ übernimmt die kleinere Datei ins Quiz.
PNG kodiert verlustfrei; Verkleinern reduziert dennoch Details und entfernt
Metadaten. Eine größere Kopie oder ein animiertes Bild wird nicht übernommen.
Die Quelldatei auf dem Gerät wird niemals verändert.
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

Im Internet läuft derselbe Zugriff unter
`/rooms/<raum>/api/media/<sha256>` über den Host des jeweiligen Raums. Der Host
prüft bei jedem Abruf den Raumzugang und die aktuelle Freigabe, auch für
Byte-Bereiche und HEAD. Es gibt keinen öffentlichen oder raumübergreifenden
Mediencache auf dem Relay. Pro Antwort wird höchstens eine 20-MiB-Datei übertragen
(rund 27 MiB Base64); die 64-MiB-Grenze des Relays bleibt unverändert.
Offene Abrufe sind begrenzt und enden bei geschlossenem Raum oder nach 20 Sekunden.

Spieler und TV laden veröffentlichte Anhänge vor Darstellung bzw. Wiedergabe
vollständig in einen sitzungsbezogenen In-Memory-LRU (maximal 60 MiB kodierte
Mediendaten). Parallele Abrufe derselben SHA-256-ID werden zusammengeführt;
höchstens vier verschiedene Dateien werden gleichzeitig heruntergeladen.
Weitere Snapshots, Wiedergaben und die Abschlussübersicht verwenden den Cache.
Die Integrität wird per SHA-256 geprüft. Ein Raum-/Zugangswechsel oder das
Schließen der Ansicht verwirft den Cache; verdrängte Dateien werden bei Bedarf
erneut geladen. Bereits ausgelieferte Inhalte lassen sich nicht zurückrufen.

**Geheimhaltung hat Vorrang:** Downloads beginnen erst mit Veröffentlichung der
Frage, nicht vor dem Rundenstart. Es werden weder zukünftige Frage-Medien noch
unveröffentlichte Lösungen vorab angefordert. Das bedeutet bewusst, dass die
Antwortzeit während eines Downloads bereits laufen kann; der Host sollte bei
medienlastigen Fragen ausreichend Zeit oder ein weiches Zeitlimit vorsehen.
YouTube und Karten bleiben externe Inhalte und werden nicht vorgeladen.
Der Ladezustand zeigt empfangene MiB und, sofern bekannt, den Gesamtfortschritt.
Die Wartezeit auf einen freien Downloadplatz und der eigentliche Download sind
jeweils auf 30 Sekunden begrenzt. Danach erscheinen eine Fehlermeldung und
„Erneut versuchen“. Andere Bedienelemente bleiben währenddessen benutzbar.

Das portable Quizformat mit eingebetteten Medien und alle bisherigen Importer
bleiben unverändert; dafür ist kein Schema-Wechsel erforderlich.

Automatisierte Regressionen decken LAN-Freigaben, echte Relay-HTTP-Abrufe für
Spieler/TV, Raumtrennung, Lösungs-Redaktion, Byte-Bereiche, Cache/Timeout/Retry
und das Übertragungsvolumen wiederholter Snapshots ab. 100 wiederholte
Cache-Zugriffe übertragen die Datei nur einmal.

Nach Änderungen relevante `flutter test`-Tests und statische Analyse ausführen.
Nur bei ausdrücklich gewünschtem lokalem Host-Build zuerst
`dart run tool/bundle_web_client.dart` ausführen; die Release-Pipeline erledigt dies
automatisch.

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
