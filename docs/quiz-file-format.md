# Quiz import and export

Open the quiz library and select **Import** to load a `.quizmo.json` file.
On a quiz card, select **Export quiz with media** to choose a save location
(or download the file in a browser). Cancelling leaves the library unchanged.
Importing a quiz whose ID is already present creates a separate copy.

A single readable JSON file contains the quiz title, description, category,
timestamps, teams, format settings (including Jeopardy boards or poker chips),
questions, scoring rules, solutions, and question and solution attachments.
Uploaded images, audio and MP4 videos travel in the file as Base64 bytes with
their MIME types and SHA-256 identifiers. Code and map settings are included;
YouTube videos and map tiles remain online references and require internet.

## Versions

Every file contains an integer `schemaVersion` at its root. The current version
is **9**. Version 2 adds `hideDetails` to media attachments; version 1 attachments default to showing details. Version 5 adds `softTimeLimit` to every question and `softPlaybackLimit` to audio attachments. Both default to `false` for historical files: hard question limits close answers automatically, and hard audio limits stop playback. Soft question limits remain open until the host ends the round; soft audio limits are advisory. Version 6 adds `manualGrading` to short-answer questions (default `false`: automatic matching). Version 7 adds `revealMode` to the Standard format (`afterEachQuestion`, the default for older files, or `atEnd`). Version 8 allows `timeLimitMs: 0` for questions without a time limit (no clock runs, the host ends the round; a speed bonus still needs a limit). Older files always have a positive limit, and 0 stays invalid in them. Version 9 stores team colours by name (`"color": "red"`) from the shared palette that the admin view also uses (`blue`, `teal`, `orange`, `purple`, `green`, `pink`, `ochre`, `cyan`, `red`, `olive`, `indigo`, `brown`, `darkTeal`, `orchid`, `slate`, `vermilion`); older files store an ARGB `colorValue`, which import maps to the nearest palette colour. Poker quiz definitions may omit predefined teams; joining players create them in the lobby. `Quiz.fromJson` selects the importer for that version before reading
question content. Every quiz model change increases the schema version. Add a
dedicated importer for each new version and update every older importer to
produce the latest in-memory model. Keep all historical importers. The single
exporter always writes the latest schema, including after importing an older file.

Version 1 files from before formats or media existed still import: a missing
`format` means Standard, and missing attachment lists mean no media. Unknown
versions, missing or noninteger versions, unknown subtype tags, invalid
solutions, and corrupt or missing uploaded bytes are rejected before saving.
Files with a schema newer than the installed app show an update prompt: update
Quizmo and retry the import. The library stays unchanged. New versions must
never silently discard unsupported content to mimic an older file.

## Limits

Files may contain at most 100 MiB of UTF-8 JSON, with at most 90 MiB of encoded
media, ten attachments per question, and 20 MiB per uploaded asset. The same
file size limit applies on export and import. MIME signatures and checksums
are validated on import, and SVG must contain only safe, self-contained content.

## Writing quiz files with an AI assistant

[ai-quiz-guide.md](ai-quiz-guide.md) (German) and
[ai-quiz-guide.en.md](ai-quiz-guide.en.md) (English) describe the complete
current format with one importable example per quiz format. It is kept in sync with the
schema by `test/core/data/ai_quiz_guide_test.dart`.
