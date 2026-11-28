# AGENTS.md — Architectural Blueprint & Constraints

This document defines the strict architectural rules and design principles for this Quiz App codebase. Any automated agent, assistant, or developer working on this project MUST follow these guidelines.

---

## 1. High-Level Vision
A cross-platform, local-first quiz platform capable of running fully standalone on mobile devices (serving web clients over LAN via embedded Dart servers) or containerized via Docker. Supports dynamic quiz styles, complex scoring engines, team/solo gameplay, and latency-compensated real-time buzzer mechanics.

---

## 2. Strict Architectural Layering

All code MUST be organized into these layers:

lib/
├── core/                # Pure Dart Domain Logic (ZERO Flutter UI imports)
│   ├── models/          # Data models (sealed unions, hand written JSON)
│   ├── engine/          # BLoC state machines, scoring algorithms, rules engine
│   ├── sync/            # NTP clock sync math, latency calculators
│   ├── protocol/        # Sealed wire messages shared by host and clients
│   ├── net/             # Platform agnostic client (http + web_socket_channel)
│   └── data/            # Question banks / seed data
├── backend/             # Server Logic (Shelf HTTP / WebSockets)
│   ├── embedded_server.dart      # dart:io implementation
│   ├── server_contract.dart      # Web safe interface + ServerEndpoint
│   ├── server_launcher*.dart     # Conditional export: io impl vs. web stub
│   ├── web_client_bundle*.dart   # Static web player sources (interface + io)
│   ├── zip_web_client_bundle.dart# Zip backed bundle, lazily inflated
│   ├── lan_addresses.dart        # Ranks local IPv4s by guest reachability
│   └── handlers/        # API, CORS, static and WebSocket message handlers
├── presentation/        # Flutter UI Components & Screens
│   ├── quizmaster/      # Quizmaster / Host Views
│   ├── player/          # Player / Web Client Views
│   └── common/          # Shared widgets (Buttons, Timers, Layouts)
└── main.dart            # Entry point

### Critical Rules:
* **Rule 1 (UI Isolation):** `lib/core/` and `lib/backend/` MUST NOT import `package:flutter/material.dart` or any UI framework code. They must remain pure Dart so they can run headlessly in standalone server/Docker environments.
* **Rule 2 (Polymorphism):** All question types, game modes, and scoring rules must use sealed classes / pattern matching (Dart 3 `sealed` hierarchies, or `freezed` unions). **Never use huge `switch-case` statements based on string IDs** for question rendering or scoring. The single permitted exception is a `fromJson` factory, i.e. the deserialization boundary.
* **Rule 3 (Clock Sync):** Never sort real-time events (like buzzers) purely by server arrival time. All client events must supply a `calculatedHostTimestamp` derived from the initial NTP-style clock handshake (`clientTimestamp - clockOffset`).
* **Rule 4 (Web Safety):** Nothing reachable from `main.dart` may import `dart:io` unconditionally. Platform specific capabilities are resolved through conditional exports (see `backend/server_launcher.dart`), because the player client ships as a Flutter Web bundle.
* **Rule 5 (Address Selection):** Never announce "the first" local IP. A device commonly has several (Wi-Fi, mobile 464XLAT, VPN, virtual adapters) and only some are reachable by a guest — the wrong pick yields `ERR_CONNECTION_TIMED_OUT`, which is indistinguishable from a firewall problem. Route every choice through `sortLanAddresses` in `backend/lan_addresses.dart` and keep the alternatives visible in the UI.

---

## 3. Tech Stack Standard

| Component | Standard Tooling |
| :--- | :--- |
| **Language** | Dart 3.x+ |
| **UI Framework** | Flutter (Web, Android, iOS, macOS) |
| **State Management** | `flutter_bloc` / BLoC pattern |
| **Data Models** | `freezed` + `json_annotation` |
| **Embedded Server** | `shelf`, `shelf_router`, `shelf_web_socket` |
| **Client Sockets** | `web_socket_channel` |
| **Auto-Discovery** | `nsd` (mDNS / Bonjour) |

---

## 4. Guidelines for Adding Features

### Adding a New Question Type
1. Add the domain model as a new union case inside `lib/core/models/question.dart` using `@freezed`.
2. Update the `QuizEngineBloc` state handler to process answers/scoring for this question type.
3. Add a dedicated widget inside `lib/presentation/player/questions/` that accepts this specific question model.
4. Add a dedicated renderer in `lib/presentation/quizmaster/` if special host controls are needed.

### Questions are format independent (Jeopardy and future formats)
A *quiz format* (`QuizFormat` in `lib/core/models/quiz_format.dart`: `StandardFormat`, `JeopardyFormat`, `PokerFormat`, `SnowflakeFormat`) only decides **how the question bank is presented and played**. It never owns question content.

* **Every question kind must work in every format** (the one exception is Biggest Snowflake, which needs a finite answer set; it asks the question through `Question.supportsUniqueness` instead of naming kinds). A Jeopardy cell references a `Question` by id and may hold *any* subtype — multiple choice, buzzer and every kind added later. Format code (`jeopardy.dart`, the Jeopardy parts of `QuizEngineBloc`, `JeopardyBoardView`, the editor board panel) must **never** `switch` on or special-case a concrete question type. Behaviour that differs per kind belongs to the `Question` hierarchy or to the existing exhaustive switches (round monitor, TV stage, player view).
* **Everything that hangs on a question belongs on `Question`, not on a format.** Future attachments such as audio, video or images (question *and* solution side) are fields of the `Question` base class, are serialized in `Question.toJson` / `baseJson` and must be redacted in `Question.redacted()` until the reveal. Because they sit on the question, every format gets them for free; do not add per-format media fields.
* **Formats only override what is format specific.** On a board the points come from the *row* (or the Daily Double wager) and replace the question's own `ScoringRule` (`QuizEngineBloc._ruleFor`); everything else (time limit, solution, buzzer fairness, clock sync) stays the question's business.
* A new question kind must be added to `kQuestionTemplates` (`question_editor.dart`) so that it can be created from a board cell,
  and to `convertQuestion` (`question_conversion.dart`, both directions through its neutral essence) so that the kind of
  an existing question can be changed in the editor. A conversion never guesses a solution and lists every loss before
  the editor asks; the change only applies with "Save question".
* Bulk editing (`QuestionBulkEdit`, editor → "Fragen gemeinsam bearbeiten") only touches the framing of a question (time limit, soft/hard, category, scoring, media details, kind specific options), never its text, answers or solution. A new kind decides in the exhaustive switch of `QuestionBulkEdit.apply` which kind specific options it takes.

### Adding a New Quiz Format
1. Add a case to the sealed `QuizFormat` (plus its `fromJson` tag) and increase the quiz `schemaVersion`. A file without a `format` entry stays a standard quiz when imported by the corresponding older-schema importer.
2. Put its static layout/rules in a pure Dart model and its live bookkeeping in a nullable field of `GameState` (see `JeopardyState`). Strip everything secret in its `redacted()` (e.g. Daily Double positions); `GameState.redactedForPlayers` must call it.
3. Drive it through new `QuizEngineEvent`s in `QuizEngineBloc`; cover the rules with tests under `test/core/engine/` before wiring UI.
4. Validate it in `Quiz.validationErrors()` (the sealed `switch` forces you to).
5. Add the host panel, the TV stage and the player view; TV and player screens render from the redacted snapshot only.

### Jeopardy format
* Board = categories (columns) × rows; `rowPoints` gives the points per row, categories may hold different numbers of cells (missing cells are empty). Rules per quiz: `penalizeWrongAnswers`, `allowSteal`; optional Daily Double flag per cell.
* The quizmaster clicks the cell the picking team asked for (`SelectJeopardyCellEvent`); the pick rotates through the teams after every question (`SetJeopardyTurnEvent` overrides it). A Daily Double first waits for `PlaceDailyDoubleWagerEvent`; the wager is capped by `QuizEngineBloc.maxDailyDoubleWager`, a miss always costs the wager and a Daily Double can never be stolen.
* The picking team answers first; with `allowSteal` a miss (or an unanswered question) restarts the question for the *other* teams (`JeopardyState.isStealRound`). The last answer of a team counts (see *Team answers*).
* `StartRoundEvent` / `NextQuestionEvent` are routed through the board in a Jeopardy session; do not bypass it.

### Adding Scoring Rules / Team Modes
* Implement rules inside `lib/core/engine/scoring_rules.dart`.
* Always write unit tests under `test/core/engine/` for any new scoring rule or team aggregation logic before connecting it to UI components.

### Adding/Editing a Quiz
1. Keep the reusable aggregate in `lib/core/models/quiz.dart`: hand-write its JSON on top of `json.dart`, including its `schemaVersion`; do not introduce generated model code.
2. Reuse `Question.fromJson` / `Question.toJson` and `Team.fromJson` / `Team.toJson`. The only string-to-subtype dispatch belongs at those deserialization boundaries; editor rendering and validation must exhaustively pattern-match the sealed hierarchy.
3. Validate an imported file fully before calling the repository. A malformed file, an unknown tag or an invalid multiple-choice solution must leave the persisted library untouched; regenerate IDs on collision instead of overwriting an existing quiz.
4. Keep persistent storage and file transfer behind conditional exports. Nothing reachable from `main.dart` may import `dart:io` unconditionally; browser persistence must work or fail loudly with an actionable explanation.
5. The host must receive the selected `Quiz` before it creates its `QuizEngineBloc`. Never swap a question bank into an already running engine: keep the existing engine, clock-sync and buzzer guarantees intact.

### Quiz file versions and compatibility
* Every change to the quiz model MUST increase the integer `schemaVersion`, including additions or changes to question types, related data types, scoring, media, format rules, serialized fields, or the meaning of saved values. Pure UI changes or error handling that do not change quiz content or its interpretation do not require a schema bump.
* Every exported quiz file MUST include its explicit integer `schemaVersion`. Select the matching importer at the deserialization boundary; never guess a version when it is missing or silently truncate a fractional version.
* Maintain a dedicated importer for EVERY schema version that has existed. When adding a new schema, add its importer and update ALL older importers to convert their files into the latest in-memory quiz model, supplying defaults or migrations as needed. Never remove old importers or silently drop questions, solutions, scoring, or media.
* Maintain one exporter and update it to write ONLY the latest schema and its version number. After importing an older file, saving or exporting it writes the latest schema; historical export implementations are not required.
* If a quiz file requires a schema newer than the installed app supports, stop the import before touching persistence and explicitly prompt the user to update Quizmo and retry. Treat malformed versions and other invalid content as validation errors, not update requests. Compatibility means newer apps can read all older files; older apps must clearly request an update for newer files.
* Cover compatibility with fixed fixtures from older releases and round-trip tests that include question and solution media. Invalid imports must leave the library untouched.
* The portable format is a single `*.quizmo.json` document: quiz metadata, format rules, teams, questions, solutions, and uploaded media bytes (Base64, MIME type, SHA-256 ID). YouTube and map attachments retain their references; their remote content is not embedded.
* Since schema 11 uploaded media have **no size limit** in the model, imports and downloads. The 20 MiB
  `maxMediaBytes` is only the editor's default upload limit, lifted by the advanced setting
  (`MediaUploadSettingsStore`). Players and TVs fetch media in `mediaChunkBytes` ranges and the relay host
  caps every response to that size (`serveMedia(maxBodyBytes:)`); never reintroduce a whole-file transfer.
* `docs/ai-quiz-guide.md` (German) and `docs/ai-quiz-guide.en.md` (English) describe the file format for AI assistants and ship in the app (settings → "Quiz mit KI erstellen", in the app language). Every schema bump MUST update both descriptions and examples; `test/core/data/ai_quiz_guide_test.dart` fails until both guides state the new `schemaVersion` and all their examples import cleanly. Team colours are palette names (`TeamColor`), never colour codes.

### Markdown
* Since quiz schema 15 `prompt`, `adminNotes`, hint texts and slide texts are Markdown (`markdown_text.dart`:
  `markdownRuns`, `markdownToPlain`, `escapeMarkdown`). Display them with `QuizMarkdown` (links open only for the host),
  edit them with `MarkdownField`, and use `markdownToPlain` wherever only plain text fits (lists, reports, CSV, PDF,
  notices). Every other field stays plain text, and player input is never Markdown.
* Importers of schema 14 and older escape the four fields, so old quizzes look as before; a recovered game with an
  older quiz escapes its slides too.

### Map questions
* `LocationQuestion` (quiz schema 16): target, optional `targetLabel`, radii `fullPointsKm` / `zeroPointsKm` (linear in
  between, great-circle distance from `core/engine/geo.dart`) and the players' start view. The target and its label are
  part of the solution and redacted. `LocationMap` (flutter_map + OpenStreetMap) is shared by editor, players and the
  result (`LocationResultView`); a tap only sets a marker, the button sends. The place search (`PlaceSearch`,
  Nominatim) runs in the editor only, on an explicit search, with nothing but the search words.

### Changing the Web Player
The embedded host serves the Flutter Web player itself, so a guest only needs
the LAN address — no install, no second web server.

1. The build is packed into `assets/web_client/bundle.zip` by
   `dart run tool/bundle_web_client.dart`; the release pipeline rebuilds it.
2. When explicitly building a host locally, rebuild this bundle first so the
   updated archive is embedded. No local build is required after an agent session.
3. The zip is a build artifact (git-ignored). A missing archive must never break
   the host: it degrades to a placeholder page plus a warning in the server log.
4. **Never** list the nested Flutter Web output directories in `pubspec.yaml`.
   `pubspec.yaml` only bundles files directly inside a declared asset folder, so
   the single zip is what keeps that list from rotting.

### Preview and real game must behave the same
The quiz preview (editor → "Preview quiz") and the hosted game must show the same views. Differences between
preview and real player/TV devices have been reported repeatedly, so every change to the host, player or TV
views MUST be checked in both, and the views are shared structurally:

1. **Host:** the game controls exist only in `buildGameSections` (`lib/presentation/quizmaster/game_sections.dart`)
   plus `JeopardyPickConfirmation` and `GameModeMenu`. `HostDashboardPage` adds only host-only sections (server,
   session access, guest Wi-Fi, recovery, server log); the preview adds only its simulation controls. Never build
   game panels (`LiveRoundPanel`, `QuestionBankPanel`, …) directly in either screen.
2. **Player:** joined players see `PlayerGameColumn` (status, device test, game, final page with protocol) inside
   `SessionNotifications`, both in `PlayerPage` and in the preview's `LocalPlayerBoard`.
3. **TV:** both render `TvScreen` from the redacted guest snapshot (`guestSnapshotOf`).
   The optional admin section "TV-Vorschau" (`TvPreviewPanel`, also in the preview) renders the same `TvScreen` through
   `TvCanvas` from the guest snapshot, as a still picture (`StillMedia`: no players, no sound, no input), never as
   a watching connection.
4. `test/presentation/preview_parity_test.dart` guards this; extend it when adding views or sections.
5. A host started with `flutter run` embeds whatever `assets/web_client/bundle.zip` is on disk. If it is stale,
   browser players and TVs miss new features although host and preview have them. The dashboard shows a red
   `OutdatedWebClientBanner` and the tech check fails ("Web-Player"); rebuild the bundle with
   `dart run tool/bundle_web_client.dart` before testing a host on real devices.

### TV instructions
* `tvInstruction` (`presentation/common/tv_instruction.dart`) tells the room what to do in the current phase, with one
  sentence per question kind in an exhaustive switch (a new kind must add its own). It is built from the guest
  snapshot only, never mentions the solution (or how many answers are right) and replaces the former "team answers" /
  "verbal" pills; the TV keeps its slot even when it is empty. Ordering items and matching terms are mixed on the TV
  (`mixed`, a seed per question) so they never look like the solution.

### Changing the TV (Spectator) Screen
`http://<host>:8080/tv` is a read-only big-screen view (smart TV browser,
streaming stick, casted tab). It is a route of the same web bundle, so rebuild
it with `dart run tool/bundle_web_client.dart` when explicitly building a host;
the release pipeline does this automatically.

1. A TV connects with `WatchRequest` (`QuizClient.watch`), **never** `JoinRequest`: no roster entry,
   no clock sync, no submissions. The hub answers with `WatchAcceptedMessage` and the redacted snapshot.
2. The TV only ever renders the redacted snapshot; never add host-only data to it.
3. `lib/presentation/spectator/` renders on a fixed 1920×1080 canvas (`TvScreen`) scaled with `FittedBox`.
   Keep text ≥ 22 px, show at most 8 leaderboard rows and switch exhaustively over the sealed `Question` hierarchy.
4. `SpectatorSessionCubit` must keep reconnecting forever (the TV runs unattended) and keep the last snapshot.
5. `main()` decides via `isTvLaunchUri(Uri.base)` *before* `runApp`, because Flutter Web rewrites the address bar.
6. Guest Wi-Fi (`GuestWifi`, `GuestWifiCubit`) is host-owned and reaches TVs only as `GuestWifiMessage` from the
   embedded LAN hub; never put it into `GameState` or player snapshots, and never forward it through the internet relay.
   Before the first question the TV lobby shows it as a second large QR code, afterwards as a small corner code.
   Credentials live in secure storage (`GuestWifiStore`). Windows reads the connected network through
   wlanapi.dll (UAC/netsh export as fallback); Android cannot read Wi-Fi passwords, so the host imports the QR
   screenshot of the system "Share Wi-Fi" screen.

---

## 5. Performance & UX Rules
* **Buzzer Responsiveness:** Always bind buzzer buttons to `Listener.onPointerDown` instead of `GestureDetector.onTap` to bypass gesture delay.
* **Bundle Size:** Keep web player assets lightweight. Defer-load host or admin tools so web players joining via QR/Discord load instantly.

* `StartRoundEvent` / `NextQuestionEvent` are routed through the board in a Jeopardy session; do not bypass it.


## 6. Required Feature Delivery
* Run the relevant tests and static analysis. Do NOT automatically build APKs, Windows executables, or web bundles, install apps, or deploy to a device at the end of an agent session. Only perform local builds/deployments when explicitly requested.
* Check the current Git branch before changing the app version in `pubspec.yaml`. On `main` and `develop`, new features normally receive a **minor** bump (`1.2.3+7` -> `1.3.0+8`) using `powershell -NoProfile -File tool/bump_version.ps1`. On these two branches, use `-Part patch` for bug-fix-only deliveries and `-Part major` for breaking app changes or an explicit user request.
* On every branch other than `main` or `develop`, take `MAJOR.MINOR.PATCH` from the branch name instead of applying an automatic semantic-version bump. For example, branch `release-1.2.0` requires `version: 1.2.0+BUILD`. This branch-derived version takes precedence over the normal minor/patch/major bump rules; do not run the default bump script on these branches. If the branch name contains no unambiguous version, ask the user instead of guessing.
* Increase the build number once per delivered feature or bug fix; never reset or reuse it. Preserve an already incremented build number when correcting the semantic version or making follow-up fixes within the same feature. Do not bump once per file.
* App versions and quiz `schemaVersion` are separate: maintain both where required.
* `.github/workflows/release.yml` owns release builds and publication. A version change pushed to `main`/`master` (or a matching `vMAJOR.MINOR.PATCH` tag/manual run) builds the web bundle, unsigned Windows installer, self-signed APK and Linux amd64 backend Docker image. After all builds/tests succeed, publish versioned images to GHCR and native downloads, Docker archive and deployment ZIP in a GitHub Release.
* `.github/workflows/beta.yml` runs the same reusable release pipeline for every push to `develop`. Beta releases, download versions and container versions use `-beta`; native versions stay numeric. Serialize beta and production publication, delete previous beta releases/tags before replacement, and remove a same-version beta when production is published. Never publish a beta for an already released production version or move production's `latest` container tag for beta builds.
* Android release keys are permanent and private. Never regenerate them per session/build or commit keys/passwords. `tool/create_android_signing.ps1` is a one-time setup outside the repository; `tool/use_android_signing.ps1` selects the same key for explicitly requested local builds. Never replace an existing key without an explicit migration request. Windows remains unsigned unless requested otherwise.
* Report the new version and verification results; distinguish local checks from CI results. Never claim an artifact or release exists before the pipeline succeeds. Do not commit, push, tag, or publish on the user's behalf unless requested.

### Private servers (Basic Auth + access links)
* The relay never authenticates itself; a reverse proxy does (`deploy/Caddyfile.basic-auth`). With
  `QUIZMO_ACCESS_KEY` set, `InternetServer` passes the key to the host socket only, and `RelayHost` appends
  `?quizmo_key=` (`kAccessKeyParameter`) to the invitation and TV links. The proxy trades it for a cookie.
* `sessionUri` keeps `quizmo_key` (like `session`) so TV QR codes and player reconnects carry it. Never send the
  key to players over the protocol and never log it.

### Pokerchips format
* `PokerFormat` stores configurable starting chips per team. Each question starts with a betting phase; the host explicitly closes betting before answers and resets the answer clock then.
* Stakes are reserved per team and may be changed until the host closes betting; replacing a stake refunds the previous reservation. A fully correct answer pays twice the stake; a wrong or absent answer loses the stake. Partial correctness has no payout. Zero stake skips scoring; teams that still have chips skip answering, but bankrupt teams may continue answering for practice without earning points or chips. This practice-only status must stay visible. Chip balances never become negative.
* Quiz templates may have no predefined teams. Teams created during joining receive the configured starting chips.
* Since quiz schema 12 `PokerFormat` has an optional `minStake` (default 0 = sitting out allowed) and `maxStake` (`null` = no limit), copied into `PokerState`. `PokerState.allowsStake` is the only range check (engine and player view); a team with fewer chips than `minStake` must go all-in. Closing the betting raises every lower or missing stake of a team with chips to the minimum.
* `PokerState.eliminations` records when a team went out (number of the played question, 0 = unknown in old saves).
  It is set after a settled question (`_reveal`) or a chip correction between questions, never by an all-in, and is
  restored when the correction that brought the team back is undone. Every ranking (host, players, TV, protocol,
  report) comes from `rankTeams` / `rankPlayers` in `lib/core/models/standings.dart`; never sort teams elsewhere.
* All question kinds use the same team chip accounting. A team is settled exactly once per question, with its valid answer (see *Team answers*); buzzer teams are settled individually. Reset restores starting chips. Players and TV use redacted snapshots, and unrevealed poker answers must not be broadcast.

### Team answers
* In a team game every team gives **one** answer (`GameState.sharesTeamAnswers`): the last one by calculated host
  timestamp, whoever sent it. Biggest Snowflake (compared per player) and buzzer rounds are excluded. `RoundState.answers`
  holds at most that one answer per team, earlier ones are in `replacedAnswers` (host only); `_withValidTeamAnswers` in
  the engine restores this after every change (also team changes and removals). A judged answer is final.
* When every team answered, `RoundState.answerDeadlineMicros` starts a countdown (`answerCountdown`) before the answers
  close; replacing restarts it. This holds for every question kind, also with a soft time limit: host graded rounds
  then go to grading, all others are revealed. Who must answer is `GameState.expectedAnswerers` (one entry per team).
* Guest snapshots withhold all answers in every format until the reveal. What one player may see (own and team answers)
  travels as `PlayerAnswers` per connection (`GameSnapshotMessage.answers`), in the preview through
  `PlayerSessionCubit.local(answers:)`.

### Drafts
* Input that is not sent yet (`AnswerDraft`) is reported by the players (`DraftMessage`, at most every 300 ms) and kept
  by the engine outside `GameState`, only the last one per player. When the answers close (expiry, end or reveal by the
  host) the engine locks the round, waits `draftGrace` for drafts under way and counts the last draft of every team (or
  player) without a sent answer, ordered and bounded by host timestamps, never by arrival
  (`RoundState.adoptedPlayerIds`, no time bonus). Every new question kind states `supportsDrafts` / `acceptsDraft`.
* Team mates see each other's drafts live (`TeamInputsView`): the hub sends `TeamDraftsMessage` (bundled, long text cut
  off) only to connected members of the same team while that team may answer, and `PlayerAnswers.drafts` with each
  snapshot. Never put drafts into `GameState`, the server log or anything other teams or TVs receive.

### Grading by the host
* Answers the host judges (manual free text, verbal rounds) are graded together in `GradingDialog`. `GradingHost` opens it
  once per round when the answers are closed (`RoundStatus.locked`), shared by dashboard and preview. The choices stay in
  the host's UI until `ConfirmGradesEvent` books all verdicts and reveals (or opens the steal round) in one state.
  Verdicts never reach guests before the reveal.

### Jokers
* A quiz has jokers only when they are configured at creation (`Quiz.jokers`, schema 12); an empty list means
  none. `Joker` is a sealed hierarchy in `lib/core/models/joker.dart`; every kind states the formats it can be
  played in (`Joker.isSupportedBy`), `Quiz.validationErrors()` rejects the others and the editor only offers
  supported kinds (`kJokerTemplates` in `joker_texts.dart`). Format code never names concrete joker kinds.
* Live bookkeeping is `GameState.jokers` (`JokerState`: uses per team, plays of the question on stage). It is
  public in guest snapshots. A team takes part in one joker per question at most (as player or target).
* Players play jokers with `UseJokerMessage` → `UseJokerEvent`; the host may play or take back
  (`RevokeJokerEvent`) on behalf of a team. A cancelled question returns its jokers and their price.
* Poker jokers (played while betting): `CreditJoker` ("Kredit", a miss only costs `maxLoss`) and
  `ForcedStakeJoker` ("Zwangseinsatz": forces `stake` on another team, locked; a miss costs `lossFactor` × the
  stake; the attacker pays `cost`). Settlement goes through `pokerSettlement` in `scoring_rules.dart`.
* Category phase: with a joker that has `beforeReveal`, every poker question starts with
  `PokerState.questionHidden` (guest snapshots carry no question, only `PokerState.category`). Order:
  category → `beforeReveal` jokers → `RevealPokerQuestionEvent` → other jokers and stakes → answers. Player
  (`PokerCategoryView`) and TV (`TvCategoryStage`) show this phase separately. Players address the round by
  `roundStartedAt`, never by a question id they cannot know yet.

### Hints
* `Question.hints` (`QuestionHint`, schema 13: text, media, `cost` in points) belong to every question kind and
  format. The host shows them in order (`ShowHintEvent`) and may take back the last one (`TakeBackHintEvent`)
  while the round is open or locked, never during poker betting. `RoundState.hintTimesMicros` holds the host
  instants; its length is the number of shown hints.
* Scoring: `applyHintDeduction` lowers only positive points, never below 0, by `RoundState.hintDeductionAt` of the
  answer's (buzzer press') host timestamp. Penalties stay with the `ScoringRule`. Poker ignores the cost
  (`GameState.hintsCostPoints`). A steal round keeps the shown hints.
* Guests receive the number and cost of all hints, but text and media only of the shown ones
  (`Question.forWire(visibleHints:)`); `serveMedia` serves only media of shown hints.
* Matching: right items with the same label are interchangeable (`MatchingQuestion._rightKey`), in accuracy and in
  `uniquenessKey`.

### Media preloading
* In the lobby players (unless switched off in their settings, `MediaPreloadSettings`) and TVs download every upload
  of the quiz **encrypted** (`MediaPreloader`, ChaCha20 in `core/net/chacha20.dart`). The host offers them once per
  connection (`MediaPreloadMessage`) under random handles at `/api/media/<handle>` (`MediaPreloadRegistry`, one random
  key per upload, created per session); the plain route keeps serving only visible media.
* Keys travel with the snapshot (`GameSnapshotMessage.mediaKeys`) only for media guests may see now
  (`visibleGuestMedia`, the same rule as `serveMedia`); never send a key earlier. The client checks the SHA-256 asset ID
  after decrypting; `SessionMediaCache` asks the preloader before it downloads.
* Devices report their progress (`MediaPreloadReport`, at most once a second) to `engine.mediaPreloadStatuses`; the
  host sees it in the start panel (`MediaPreloadStatusView`). YouTube and maps cannot be preloaded and count as online.

### Media playback
* `MediaPlayback` (`presentation/common/media_playback.dart`) states what a view may do: the TV plays `automatic`, player
  devices and the host's device only `onDemand` (never by themselves, whatever the host pressed), `stopped` media stand
  still but may be started, `paused` (host command, buzzer) locks playback on every device. Always derive it with
  `MediaPlayback.onTv` / `onDevice`; the commands also serve slides, and the pause ends with the next question or slide.
* After the reveal only the solution media are on screen when there are some (`visibleQuestionMedia` in
  `common/reveal_media.dart`); the hidden side is removed, so question and solution audio never play together.
  Media of shown hints belong to the question side (players hide them after the reveal, the TV drops hints).
  `RevealMediaToggle` switches back: on the host it sends `ShowRevealMediaEvent` and the TV follows
  `RoundState.showsQuestionMedia`, players switch locally (`LocalRevealMedia`). Every new question starts again.
* Audio, MP4 and YouTube share one control row: `MediaTimeline` (times only, never a title) and on the TV
  `MediaVolumeControl` (`MediaVolume`, stored on the TV). A jump on the host (`MediaSeekReporter` around the live
  round) becomes `SeekTvMediaEvent` → `GameState.tvMediaSeek`, which the TV follows (`MediaSeekCommand`,
  `FollowsHostSeek`); jumps of players stay on their device.
* A TV whose browser refuses to start sound reports it (`MediaBlockedReport` → `QuizEngineBloc.mediaScreens`).

### Media size
* `QuestionMediaView` shows media as large as the space allows. In scrolling pages: full width, at most `maxMediaHeight`
  (default 60 % of the screen); with `fill` (TV) media share the bounded space of the parent, without scrolling.
  On the TV pictures (with zoom), MP4 videos and maps have a corner button that shows them on almost the whole screen
  (`_Enlargeable`, moved with a `GlobalKey` so a video keeps running); never replace it by a dialog with a new player.
  Enlarged pictures can be zoomed and moved (`InteractiveViewer`, buttons, + / − / 0); the zoom resets on closing. Every picture, video and map gets a bounded box whose height is reserved from `MediaAsset.aspectRatio`
  (read from the bytes, sent with references in `forWire`, never stored in quiz files) while it loads.
* On the TV media are always the first child of the row in `_QuestionStage`, so a video keeps running when the layout
  changes; answers stand next to them and scale down instead of scrolling.

### Interstitial slides
* `Quiz.slides` (`InfoSlide`, schema 12): unscored screens with title, text and media, placed before a
  question (`beforeQuestionId`, `null` = at the end). They are not questions and never enter the question
  bank, scoring, reports or format rules.
* `GameState.slides` is host-only (stripped like the question bank); `GameState.activeSlide` is public
  (`forWire`) and its media are served like question media. `ShowSlideEvent` works only between questions,
  starting a question hides the slide. TV and player render `InfoSlideView` while `GameState.showsSlide`.

### Biggest Snowflake format
* `SnowflakeFormat` (quiz schema 10) stores **no solutions**: the rarest answer of a round wins. `scoring` is `winnerOnly` (only the rarest answer scores) or `graded` (the share falls linearly with every step of more common answers; the most common one earns nothing). The shares come from `snowflakeShares` in `scoring_rules.dart`: equally rare answers share a step, and when at least two participants answer and all agree nobody scores.
* Only kinds with a finite, deterministic answer set can be played. A kind opts in through `Question.supportsUniqueness` / `Question.uniquenessKey` (multiple choice, true/false, ordering, matching); format code never names concrete kinds. A new kind with such an answer set overrides both.
* Questions of a snowflake quiz have no solution: `Quiz.validationErrors()` rejects stored solutions and unsupported kinds, the importer and the editor strip solutions with `Question.withoutSolution()`, and a solution-less question is only valid in this format (`structureErrors` vs. `solutionErrors`).
* The points are the question's own `ScoringRule` multiplied by the share. Answers are compared per player, also in team mode.
* `GameState.snowflake` carries the rule; every `RoundState` of the session is stamped with it, and `RoundState.accuracyFor` / `snowflakeGroups` derive shares from the submitted answers. Guest snapshots withhold all answers until the reveal (`hiddenAnswerCount` keeps the count), so nobody can copy the minority. Views show `SnowflakeResultView` instead of a solution.

### Admin view sections
* `DashboardSection.required` marks sections the game cannot run without. The recovery status is optional and hidden by default: saving runs in `SessionRecovery` regardless of the section. `DashboardSectionGrid.forceVisible` still shows it first while a recovered game waits to be resumed or saving fails; never make resuming depend on a hidden section.
* `DashboardLayout.defaultOrder` (not the enum order) is the default position. It keeps the scoreboard and the corrections side by side in a running game; sections that only exist at times follow them. `dashboard_layout_test.dart` guards this.
