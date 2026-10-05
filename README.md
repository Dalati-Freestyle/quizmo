# Quizmo

A local-first, multi-device quiz platform. One device hosts an **embedded HTTP
and WebSocket server** inside the Flutter app process; phones, tablets and
browsers on the same network join it as players. Buzzer races are decided by
**latency-compensated timestamps**, not by who happens to sit closest to the
access point.

---

## 1. Architecture at a glance

```text
┌──────────────────────── Host device (phone / desktop) ────────────────────────┐
│                                                                               │
│   lib/presentation/quizmaster       lib/backend                               │
│   ┌────────────────────┐   events   ┌────────────────────────┐                │
│   │ HostDashboardPage  │──────────► │ EmbeddedServer (shelf) │                │
│   │ HostServerCubit    │            │  /api/health           │                │
│   └─────────┬──────────┘            │  /api/sync-time  ◄─────┼── clock probe  │
│             │                       │  /api/state            │                │
│             │ BlocProvider          │  /ws            ◄──────┼── live socket  │
│             ▼                       └───────────┬────────────┘                │
│   ┌───────────────────────────────────────┐     │ snapshots                   │
│   │ QuizEngineBloc  (lib/core/engine)     │◄────┘                             │
│   │  · single source of truth             │                                   │
│   │  · pure Dart, zero Flutter imports    │                                   │
│   └───────────────────────────────────────┘                                   │
└───────────────────────────────────────────────────────────────────────────────┘
                              ▲                      ▲
                 ws + http    │                      │    ws + http
                   ┌──────────┴─────────┐ ┌──────────┴─────────┐
                   │ Player (browser)   │ │ Player (phone)     │
                   │ QuizClient +       │ │ QuizClient +       │
                   │ ClockSyncEstimator │ │ ClockSyncEstimator │
                   └────────────────────┘ └────────────────────┘
```

### Layering rules

| Layer | May import | Must **not** import |
| --- | --- | --- |
| `lib/core/` | `bloc`, `equatable`, `http`, `web_socket_channel` | anything Flutter, `dart:io` |
| `lib/backend/` | `shelf*`, `dart:io`, `lib/core/` | anything Flutter |
| `lib/presentation/` | Flutter, `flutter_bloc`, `lib/core/`, `lib/backend/` | — |

`lib/core` stays head-less on purpose: the exact same `QuizEngineBloc` can be
hosted by a Flutter app, by a `dart run` binary or by a Docker container.

---

## 2. Folder structure

```text
lib/
├── core/                              # Pure Dart. No Flutter. No dart:io.
│   ├── data/
│   │   ├── quiz_import_export.dart    # validated standalone *.quizmo.json files
│   │   ├── quiz_repository.dart       # pure Dart library contract + JSON store
│   │   └── sample_quiz.dart           # demo seed / fallback question bank + teams
│   ├── engine/
│   │   ├── quiz_engine_bloc.dart      # the state machine
│   │   ├── quiz_engine_event.dart     # StartRound / SubmitAnswer / BuzzerPress / TimeSync / …
│   │   ├── quiz_engine_state.dart     # GameState + transient host notice
│   │   └── scoring_rules.dart         # sealed ScoringRule hierarchy
│   ├── models/
│   │   ├── answer.dart                # sealed AnswerSubmission → MultipleChoiceAnswer | BuzzerPress
│   │   ├── game_state.dart            # GameState + sealed GameMode (SoloMode | TeamMode)
│   │   ├── json.dart                  # hand written JSON plumbing
│   │   ├── models.dart                # barrel
│   │   ├── player.dart                # Player (name, team, clock quality)
│   │   ├── question.dart              # sealed Question → MultipleChoiceQuestion | BuzzerQuestion
│   │   ├── quiz.dart                  # reusable, versioned Quiz aggregate
│   │   ├── round.dart                 # RoundState + RoundStatus
│   │   ├── score.dart                 # ScoreState + ScoreEvent history
│   │   └── team.dart                  # Team
│   ├── net/
│   │   └── quiz_client.dart           # platform agnostic player client
│   ├── protocol/
│   │   └── messages.dart              # sealed ClientMessage / ServerMessage
│   └── sync/
│       ├── clock.dart                 # injectable NowMicros clock
│       └── clock_sync.dart            # ClockSample + ClockSyncEstimator (NTP style)
├── backend/                           # Server logic. No Flutter.
│   ├── embedded_server.dart           # shelf host (dart:io only)
│   ├── server_contract.dart           # EmbeddedQuizServer interface, ServerEndpoint (web safe)
│   ├── server_launcher.dart           # conditional export → io | stub
│   ├── server_launcher_io.dart
│   ├── server_launcher_stub.dart      # browsers cannot listen: fails loudly
│   ├── web_client_bundle.dart         # WebClientBundle interface (web safe)
│   ├── web_client_bundle_io.dart      # directory / zip-file sources (dart:io)
│   ├── zip_web_client_bundle.dart     # zip backed bundle, inflated lazily
│   ├── lan_addresses.dart             # ranks local IPv4s by reachability
│   └── handlers/
│       ├── api_handlers.dart          # /api/health, /api/sync-time, /api/state
│       ├── cors_middleware.dart       # required for browser players
│       ├── socket_handlers.dart       # SocketHub: connections ⇄ engine events
│       └── static_handlers.dart       # serves the bundled Flutter Web player
├── presentation/                      # Flutter UI.
│   ├── app.dart                       # MaterialApp + Material 3 theme
│   ├── common/
│   │   ├── adaptive_layout.dart       # FormFactor, AdaptivePanelGrid, PanelCard
│   │   ├── bundled_web_client.dart    # rootBundle → WebClientBundle adapter
│   │   ├── buzzer_button.dart         # Listener.onPointerDown buzzer
│   │   ├── role_selection_page.dart
│   │   └── scoreboard_view.dart       # solo vs team standings
│   ├── player/
│   │   ├── player_page.dart           # join form + live board in one route
│   │   ├── player_session_cubit.dart
│   │   └── questions/
│   │       ├── buzzer_question_view.dart
│   │       └── multiple_choice_question_view.dart
│   └── quizmaster/
│       ├── dashboard_panels.dart      # server / players / bank / live round / log
│       ├── editor/
│       │   ├── quiz_library_page.dart # choose, import, export, and manage quizzes
│       │   ├── quiz_editor_page.dart  # metadata, teams, order, and question bank
│       │   ├── question_editor.dart   # exhaustive MC / buzzer + scoring editor
│       │   └── quiz_*_{io,web,stub}.dart # conditional persistence / transfer
│       ├── host_dashboard_page.dart
│       └── host_server_cubit.dart
└── main.dart

test/
├── backend/bundled_web_client_test.dart # real bundle.zip → HTTP (skips if absent)
├── backend/embedded_server_test.dart  # real server + 2 real clients over loopback
├── backend/lan_addresses_test.dart    # which local IP to announce
├── backend/static_handlers_test.dart  # MIME types, SPA fallback, traversal
├── core/engine/quiz_engine_bloc_test.dart
├── core/engine/scoring_rules_test.dart
├── core/data/quiz_import_export_test.dart
├── core/data/quiz_repository_test.dart
├── core/models/quiz_test.dart
├── core/protocol/messages_test.dart
├── core/sync/clock_sync_test.dart
├── presentation/buzzer_button_test.dart
├── presentation/quizmaster/editor/quiz_editor_page_test.dart
└── widget_test.dart

tool/
└── bundle_web_client.dart             # flutter build web → assets/web_client/bundle.zip
```

---

## 3. Running the prototype

### 3.0 Bundle the web player (once, and after every player UI change)

```powershell
dart run tool/bundle_web_client.dart
```

This runs `flutter build web` and packs the result into
`assets/web_client/bundle.zip`. The host then serves that build at `/`, so a
guest joins by simply opening the LAN address in **any** browser — no install,
no second web server, no `flutter run -d chrome` needed.

Skip it and everything still works; the host just serves a placeholder page at
`/` and says so in the dashboard and the server log.

### 3.1 Host + two browser players (recommended demo)

```powershell
# Terminal 1 – the host (Windows / macOS / Linux / Android / iOS)
flutter run -d windows
```

1. On the host: **Host a quiz → choose a quiz → Host this quiz**, then start the
   server. The library persists locally across restarts and seeds the bundled
   sample quiz if it is empty. The dashboard shows the LAN URL, for example
   `http://192.168.1.42:8080` (tap to copy).
2. Open that URL on any phone or laptop on the same Wi-Fi. The bundled player
   loads straight from the host and pre-fills its own origin as the host
   address, so guests only enter a name and pick a team.
3. On the host: start **“Which city is the capital of Australia?”** — both
   players answer, the round auto-reveals and speed bonuses are booked.
4. Start **“Which chemical element has the symbol Au?”** — both players hammer
   the buzzer. After a 350 ms grace window the host shows the ranking with the
   millisecond gap and hands the floor to the true winner.
5. Judge the spoken answer with **“… is right”** / **“Wrong”**.

During UI development `flutter run -d chrome` still works as a player; it talks
to the host over CORS instead of same-origin.

### 3.2 Everything on one device

Start the server, then use the *person-add* icon in the dashboard app bar to
open a second, loopback-connected player state inside the same app.

### Windows desktop app

The native Windows app includes the quiz library and editor, all question
types and quiz formats, the host dashboard, local persistence, file import and
export, and the embedded server for browser players and the TV screen. Audio
uploads (including playback limits) and MP4 video play inside the app; YouTube
attachments open in the default browser. Video codecs come from Windows.

To build it, install Flutter and Visual Studio 2022 or newer with the
**Desktop development with C++** workload, including MSVC, CMake tools and
the Windows SDK. Enable Windows Developer Mode if Flutter reports that plugin
symlinks are unavailable. Check the setup with `flutter doctor -v`.

```powershell
flutter pub get
dart run tool/bundle_web_client.dart
flutter run -d windows
```

For a distributable release, run `flutter build windows --release` after
bundling the web client. Launch
`build/windows/x64/runner/Release/quizmo.exe`. Distribute the **entire Release
folder**, including its DLLs and `data` folder. The target PC needs the
Microsoft Visual C++ Redistributable for x64, but does not need Flutter or
Visual Studio.

Start hosting from **Host a quiz**, then let guests open the LAN address shown
on the dashboard. The TV uses the same address with `/tv` appended. Allow Quizmo
through Windows Firewall on private networks for the chosen server port
(8080 by default); keep the alternative LAN addresses visible when using VPNs
or multiple network adapters.

### 3.3 Deep link for players

`http://localhost:port/#/?host=http://192.168.1.42:8080` — the join form reads
the `host` query parameter, so a QR code or a Discord message is enough to get
somebody into the game.

### 3.3.1 “The address times out” — picking the right local IP

A phone usually has **more than one** IPv4 address, and only one of them is
routable for a guest. A Pixel on Wi-Fi *and* mobile data reports both:

```text
wlan0        192.168.2.188/24   ← the LAN address a guest can reach
v4-rmnet16   192.0.0.4/32       ← RFC 7335 464XLAT translation address
```

Announcing the second one produces `ERR_CONNECTION_TIMED_OUT` on every guest —
a *timeout*, not “connection refused”, because nothing routes there at all.
`lan_addresses.dart` therefore ranks every discovered address (RFC 1918 space on
a `wlan`/`eth` interface wins; CGNAT, link-local and the service-continuity
prefix lose) and the dashboard announces the best one. The runner-ups stay
visible as copy-to-clipboard chips, so an unusual setup is one tap away from
working.

If a guest still times out, check in this order:

1. **Same network?** Guest on mobile data, or on a 5 GHz/guest SSID that is
   isolated from the host, will always time out.
2. **AP/client isolation** in the router — many guest networks block
   device-to-device traffic by design.
3. **Host firewall** when hosting from Windows: allow inbound TCP 8080 for
   private networks.
4. Try the alternative address chips on the dashboard.

### 3.4 Quality gates

```powershell
flutter analyze          # 0 issues
flutter test             # 94 tests
flutter build web        # proves the conditional dart:io import
```

### 3.5 Android specifics

`android/app/src/main/AndroidManifest.xml` carries two things a stock Flutter
template does not:

* **`INTERNET` permission.** Flutter only adds it to the *debug* and *profile*
  manifests. Without it in `main`, a release build cannot open the listening
  socket and hosting fails with a `SocketException`.
* **`networkSecurityConfig` with cleartext enabled.** Android 9 (API 28) blocks
  plain HTTP by default, which would stop this device from *joining* a host.
  There are no certificates for `http://192.168.2.188:8080`, and `<domain>`
  entries cannot express RFC 1918 ranges, so cleartext is allowed globally —
  see the comment in `res/xml/network_security_config.xml`.

---

## 4. The three design decisions that matter

### 4.1 Polymorphic questions (architecture Rule 2)

`Question` is a Dart 3 `sealed` class. Rendering and scoring dispatch through
exhaustive pattern matching, so adding `EstimationQuestion` is a **compile time
guided** refactor — the analyzer lists every site that still has to handle it:

```dart
// lib/presentation/player/player_page.dart
return switch (question) {
  MultipleChoiceQuestion() => MultipleChoiceQuestionView(...),
  BuzzerQuestion()         => BuzzerQuestionView(...),
};
```

The only place that maps a *string tag* to a type is `Question.fromJson` — the
deserialization boundary, where a wire format has to be decoded exactly once.

Scoring is equally pluggable: `FixedPointsRule`, `SpeedBonusRule` and
`FirstBuzzerRule` implement `ScoreDelta evaluate(ScoringContext)`. Because the
context only carries primitives (`isCorrect`, `elapsed`, `timeLimit`, `rank`),
any rule works with any question kind.

### 4.2 Clock synchronisation (architecture Rule 3)

**Sign convention:** `clockOffset = clientClock − hostClock`, therefore

```text
hostTimestamp = clientTimestamp − clockOffset
```

Handshake, Cristian's algorithm:

```text
t0  client sends  ──────────────►
                                   t1  host stamps the request
t2  client receives ◄──────────────

roundTrip   = t2 − t0
clockOffset = (t0 + t2) / 2 − t1
```

`ClockSyncEstimator` keeps a sliding window of probes and, exactly like NTP,
trusts the sample with the **lowest round trip time** — a fast probe had the
least opportunity to be distorted by asymmetric queueing delay.

The domain model enforces the rule so it cannot be bypassed:

```dart
// lib/core/models/answer.dart
int get hostTimestampMicros => clientTimestampMicros - clockOffsetMicros;
```

**Buzzer grace window.** The engine never locks on the first packet it receives.
The first press opens a 350 ms window; every press that lands inside is merged
into the queue, the queue is re-sorted by `hostTimestampMicros`, and only then
is the floor awarded. That is what allows a player on a slow link to win a race
they actually won — covered by
`test/core/engine/quiz_engine_bloc_test.dart › declares the fastest press even
when it arrives last`.

### 4.3 Buzzer responsiveness

`GestureDetector.onTap` only fires after the gesture arena resolves the pointer
sequence — at minimum after pointer-up, and much later when an ancestor
scrollable competes. `BuzzerButton` therefore uses `Listener.onPointerDown` and
timestamps the press before any animation or haptic call:

```dart
void _handlePointerDown(PointerDownEvent event) {
  if (widget.mode != BuzzerMode.ready) return;
  setState(() => _isDown = true);
  widget.onPressed();               // fire first
  unawaited(HapticFeedback.heavyImpact());
}
```

`test/presentation/buzzer_button_test.dart` asserts that the callback runs
*before* the pointer is lifted and that it still works inside a `ListView`.

---

## 5. Network contract

### REST

| Method | Path | Body / Response |
| --- | --- | --- |
| `GET` | `/api/health` | `{ status, serverName, hostTimeMicros, players }` |
| `POST` | `/api/sync-time` | in `{ clientSentAtMicros }` → out `{ clientSentAtMicros, hostTimeMicros }` |
| `GET` | `/api/state` | redacted `GameState` snapshot (polling fallback) |
| `GET` | `/ws` | WebSocket upgrade |
| `GET`/`HEAD` | `/<anything>` | the bundled Flutter Web player (SPA fallback to `index.html`) |

The static catch-all is registered **last**, so `/api/**` and `/ws` always win.
Requests that carry a file extension never fall back to `index.html` — a missing
`main.dart.js` has to surface as a `404` instead of silently returning HTML.
Encoded separators (`%2f`, `%2e`) are rejected with `403` rather than decoded.

All responses carry permissive CORS headers because browser players may load the
Flutter bundle from a different origin than the hosting phone (for example from
a `flutter run -d chrome` dev server).

### WebSocket

| Direction | Message | Purpose |
| --- | --- | --- |
| C → S | `join` | register a name / team, report the measured offset |
| C → S | `syncPing` | re-probe the clock on the open socket (every 10 s) |
| C → S | `clockReport` | publish the refreshed offset to the host |
| C → S | `submission` | polymorphic envelope: `multipleChoice` **or** `buzzer` |
| C → S | `leave` | graceful disconnect |
| S → C | `welcome` | connection id, host clock, server name |
| S → C | `joinAccepted` | authoritative `playerId` |
| S → C | `syncPong` | echoed `t0` plus host `t1` |
| S → C | `snapshot` | redacted `GameState` after every engine transition |
| S → C | `error` | rejected frame, socket stays open |

**Redaction.** `GameState.redactedForPlayers()` strips the upcoming question
bank and the solution of the running round; the solution is re-attached only
once the host reveals. A player can never read the answer out of the network
tab.

**Identity.** The socket connection is the source of truth: the hub rewrites
every inbound submission with `submission.withPlayerId(connection.playerId)`, so
a client cannot buzz on somebody else's behalf.

---

## 6. Conventions

* **Instants** travel as microseconds since the Unix epoch (`...Micros`).
* **Durations** travel as milliseconds (`...Ms`).
* Time is read through the injectable `NowMicros` typedef, which is what makes
  every scoring and buzzer rule deterministically testable.

---

## 7. Extending the prototype

### Adding a question type

1. Add a subclass to `lib/core/models/question.dart` and register its tag in
   `Question.fromJson`.
2. Run `flutter analyze` — every non-exhaustive `switch` is now an error. Fix
   `QuizEngineBloc._onRevealRound`, `LiveRoundPanel` and `_QuestionStage`.
3. Add the player widget under `lib/presentation/player/questions/`.

### Adding a scoring rule

1. Add a subclass to `lib/core/engine/scoring_rules.dart` and register its tag.
2. Add a unit test under `test/core/engine/` **before** wiring it into the UI.

### Creating and editing a quiz

1. Open **Manage quiz library** on the start screen. Create a quiz or edit the
   seeded sample, then configure its name, description, category and optional
   teams.
2. Add, edit, delete or drag questions into order. The editor supports both
   `MultipleChoiceQuestion` and `BuzzerQuestion`, their time limits and every
   existing `ScoringRule` configuration.
3. Use the menu on a library card to export one human-readable
   `*.quizmo.json` document, or use the import button to select one. Imports
   validate JSON, schema version, question/rule tags and multiple-choice
   solutions before touching local storage. A colliding ID is regenerated, so
   importing never overwrites an existing quiz.
4. The library is stored locally with `shared_preferences`: on web it is
   browser-local, while native platforms use their local application storage.
   File picking and downloads/sharing are platform-aware; unsupported targets
   fail with a visible explanation rather than silently discarding data.

The quizmaster/editor route is defer-loaded from the role screen. Browser
players therefore do not load host administration code on their initial path.

### Known gaps (deliberate for an MVP)

* **`freezed` / `json_serializable`** are declared in `pubspec.yaml` but not yet
  used. The models are hand written Dart 3 `sealed` classes: identical
  ergonomics, exhaustive pattern matching, zero generated files to keep in sync
  while the domain is still moving. Migrating later is mechanical — the public
  API of every model already matches what `freezed` would emit.
* **`nsd` (mDNS auto discovery)** is declared but unused; players type or scan
  the LAN URL. The `ServerEndpoint` model is the natural place to plug it in.
* No authentication: anybody on the LAN can join, which is the point for a
  living-room quiz but not for the public internet.

