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
A *quiz format* (`QuizFormat` in `lib/core/models/quiz_format.dart`: `StandardFormat`, `JeopardyFormat`) only decides **how the question bank is presented and played**. It never owns question content.

* **Every question kind must work in every format.** A Jeopardy cell references a `Question` by id and may hold *any* subtype — multiple choice, buzzer and every kind added later. Format code (`jeopardy.dart`, the Jeopardy parts of `QuizEngineBloc`, `JeopardyBoardView`, the editor board panel) must **never** `switch` on or special-case a concrete question type. Behaviour that differs per kind belongs to the `Question` hierarchy or to the existing exhaustive switches (round monitor, TV stage, player view).
* **Everything that hangs on a question belongs on `Question`, not on a format.** Future attachments such as audio, video or images (question *and* solution side) are fields of the `Question` base class, are serialized in `Question.toJson` / `baseJson` and must be redacted in `Question.redacted()` until the reveal. Because they sit on the question, every format gets them for free; do not add per-format media fields.
* **Formats only override what is format specific.** On a board the points come from the *row* (or the Daily Double wager) and replace the question's own `ScoringRule` (`QuizEngineBloc._ruleFor`); everything else (time limit, solution, buzzer fairness, clock sync) stays the question's business.
* A new question kind must be added to `kQuestionTemplates` (`question_editor.dart`) so that it can be created from a board cell.

### Adding a New Quiz Format
1. Add a case to the sealed `QuizFormat` (plus its `fromJson` tag). A file without a `format` entry stays a standard quiz, so `schemaVersion` does not change for purely additive formats.
2. Put its static layout/rules in a pure Dart model and its live bookkeeping in a nullable field of `GameState` (see `JeopardyState`). Strip everything secret in its `redacted()` (e.g. Daily Double positions); `GameState.redactedForPlayers` must call it.
3. Drive it through new `QuizEngineEvent`s in `QuizEngineBloc`; cover the rules with tests under `test/core/engine/` before wiring UI.
4. Validate it in `Quiz.validationErrors()` (the sealed `switch` forces you to).
5. Add the host panel, the TV stage and the player view; TV and player screens render from the redacted snapshot only.

### Jeopardy format
* Board = categories (columns) × rows; `rowPoints` gives the points per row, categories may hold different numbers of cells (missing cells are empty). Rules per quiz: `penalizeWrongAnswers`, `allowSteal`; optional Daily Double flag per cell.
* The quizmaster clicks the cell the picking team asked for (`SelectJeopardyCellEvent`); the pick rotates through the teams after every question (`SetJeopardyTurnEvent` overrides it). A Daily Double first waits for `PlaceDailyDoubleWagerEvent`; the wager is capped by `QuizEngineBloc.maxDailyDoubleWager`, a miss always costs the wager and a Daily Double can never be stolen.
* The picking team answers first; with `allowSteal` a miss (or an unanswered question) restarts the question for the *other* teams (`JeopardyState.isStealRound`). On a board only the first answer of a team counts.
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

### Changing the Web Player
The embedded host serves the Flutter Web player itself, so a guest only needs
the LAN address — no install, no second web server.

1. The build is packed into `assets/web_client/bundle.zip` by
   `dart run tool/bundle_web_client.dart`; re-run it after every player UI change.
2. Rebuild the host app afterwards so the updated archive is embedded.
3. The zip is a build artifact (git-ignored). A missing archive must never break
   the host: it degrades to a placeholder page plus a warning in the server log.
4. **Never** list the nested Flutter Web output directories in `pubspec.yaml`.
   `pubspec.yaml` only bundles files directly inside a declared asset folder, so
   the single zip is what keeps that list from rotting.

### Changing the TV (Spectator) Screen
`http://<host>:8080/tv` is a read-only big-screen view (smart TV browser,
streaming stick, casted tab). It is a route of the same web bundle, so rebuild
it with `dart run tool/bundle_web_client.dart` after every change.

1. A TV connects with `WatchRequest` (`QuizClient.watch`), **never** `JoinRequest`: no roster entry,
   no clock sync, no submissions. The hub answers with `WatchAcceptedMessage` and the redacted snapshot.
2. The TV only ever renders the redacted snapshot; never add host-only data to it.
3. `lib/presentation/spectator/` renders on a fixed 1920×1080 canvas (`TvScreen`) scaled with `FittedBox`.
   Keep text ≥ 22 px, show at most 8 leaderboard rows and switch exhaustively over the sealed `Question` hierarchy.
4. `SpectatorSessionCubit` must keep reconnecting forever (the TV runs unattended) and keep the last snapshot.
5. `main()` decides via `isTvLaunchUri(Uri.base)` *before* `runApp`, because Flutter Web rewrites the address bar.

---

## 5. Performance & UX Rules
* **Buzzer Responsiveness:** Always bind buzzer buttons to `Listener.onPointerDown` instead of `GestureDetector.onTap` to bypass gesture delay.
* **Bundle Size:** Keep web player assets lightweight. Defer-load host or admin tools so web players joining via QR/Discord load instantly.

* `StartRoundEvent` / `NextQuestionEvent` are routed through the board in a Jeopardy session; do not bypass it.
