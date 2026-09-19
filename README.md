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
│   │   └── sample_quiz.dart           # const demo question bank + teams
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
│   └── handlers/
│       ├── api_handlers.dart          # /api/health, /api/sync-time, /api/state
│       ├── cors_middleware.dart       # required for browser players
│       └── socket_handlers.dart       # SocketHub: connections ⇄ engine events
├── presentation/                      # Flutter UI.
│   ├── app.dart                       # MaterialApp + Material 3 theme
│   ├── common/
│   │   ├── adaptive_layout.dart       # FormFactor, AdaptivePanelGrid, PanelCard
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
│       ├── host_dashboard_page.dart
│       └── host_server_cubit.dart
└── main.dart

test/
├── backend/embedded_server_test.dart  # real server + 2 real clients over loopback
├── core/engine/quiz_engine_bloc_test.dart
├── core/engine/scoring_rules_test.dart
├── core/protocol/messages_test.dart
├── core/sync/clock_sync_test.dart
├── presentation/buzzer_button_test.dart
└── widget_test.dart
```

---

## 3. Running the prototype

### 3.1 Host + two browser players (recommended demo)

```powershell
# Terminal 1 – the host (Windows / macOS / Linux / Android / iOS)
flutter run -d windows

# Terminal 2 – player A
flutter run -d chrome

# Terminal 3 – player B (or simply open a second tab of the URL from above)
flutter run -d chrome
```

1. On the host: **Host a quiz → Start server**. The dashboard shows the LAN URL,
   for example `http://192.168.1.42:8080` (tap to copy).
2. In each browser tab: **Join as player**, paste the host URL, enter a name,
   pick *Red Foxes* / *Blue Whales*, then **Connect and sync clock**.
   The client runs five `POST /api/sync-time` probes before the socket opens.
3. On the host: start **“Which city is the capital of Australia?”** — both
   players answer, the round auto-reveals and speed bonuses are booked.
4. Start **“Which chemical element has the symbol Au?”** — both players hammer
   the buzzer. After a 350 ms grace window the host shows the ranking with the
   millisecond gap and hands the floor to the true winner.
5. Judge the spoken answer with **“… is right”** / **“Wrong”**.

### 3.2 Everything on one device

Start the server, then use the *person-add* icon in the dashboard app bar to
open a second, loopback-connected player state inside the same app.

### 3.3 Deep link for players

`http://localhost:port/#/?host=http://192.168.1.42:8080` — the join form reads
the `host` query parameter, so a QR code or a Discord message is enough to get
somebody into the game.

### 3.4 Quality gates

```powershell
flutter analyze          # 0 issues
flutter test             # 57 tests
flutter build web        # proves the conditional dart:io import
```

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

All responses carry permissive CORS headers because browser players load the
Flutter bundle from a different origin than the hosting phone.

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

### Known gaps (deliberate for an MVP)

* **`freezed` / `json_serializable`** are declared in `pubspec.yaml` but not yet
  used. The models are hand written Dart 3 `sealed` classes: identical
  ergonomics, exhaustive pattern matching, zero generated files to keep in sync
  while the domain is still moving. Migrating later is mechanical — the public
  API of every model already matches what `freezed` would emit.
* **`nsd` (mDNS auto discovery)** is declared but unused; players type or scan
  the LAN URL. The `ServerEndpoint` model is the natural place to plug it in.
* No persistence: a host restart clears the session.
* No authentication: anybody on the LAN can join, which is the point for a
  living-room quiz but not for the public internet.

