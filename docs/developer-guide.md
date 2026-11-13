# Developer guide

Architecture, building, releases, the network contract and how to extend
Quizmo. The binding rules for contributors and agents are in
[AGENTS.md](../AGENTS.md). Back to the [overview](../README.md).

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
│   ├── server_launcher.dart           # conditional export → io | web | stub
│   ├── server_launcher_io.dart
│   ├── server_launcher_web.dart       # browser host → same-origin relay
│   ├── server_launcher_stub.dart      # unsupported platform fallback
│   ├── relay_host.dart                # browser engine → virtual player connections
│   ├── internet_server.dart           # isolated room relay + static website
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

## 3. Running from source

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
   server. The library persists locally across restarts and contains the bundled
   Standard, Jeopardy and Poker example quizzes. The dashboard shows the LAN URL, for example
   `http://192.168.1.42:8080` (tap to copy).
2. Open that URL on any phone or laptop on the same Wi-Fi. The bundled player
   loads straight from the host and pre-fills its own origin as the host
   address, so guests only enter a name and pick a team.
3. Start the quiz, then the first question of the Standard example
   (**“Welche Stadt ist die Hauptstadt von Australien?”**) — both players
   answer, the round reveals and speed bonuses are booked.
4. Start **“Welches chemische Element hat das Symbol „Au“?”** — both players hammer
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

### Automated versioned releases

Local APK, EXE, web-bundle builds and device installations are **not** required
after agent sessions. Agents still run relevant tests and static analysis and
increase `pubspec.yaml` once per delivered feature. Default: minor version,
patch reset to zero, build number incremented (for example `1.2.3+7` becomes
`1.3.0+8`). Bug-fix-only deliveries use patch; breaking changes use major.
Quiz file `schemaVersion` remains an independent compatibility version.

```powershell
powershell -NoProfile -File tool/bump_version.ps1                 # minor
powershell -NoProfile -File tool/bump_version.ps1 -Part patch
powershell -NoProfile -File tool/bump_version.ps1 -Part major -DryRun
```

Commit the feature and version change together. After pushing a changed
`pubspec.yaml` to `main` or `master`, `.github/workflows/release.yml` runs
analysis/tests, builds the current player/TV web bundle, and builds Android,
Windows and the Docker backend on GitHub runners. Only after **all** builds
and the Docker health check succeed does it publish the container and create a
GitHub Release and its `vMAJOR.MINOR.PATCH` tag at that commit. A matching tag
push or **Actions → Release → Run workflow** also works. Existing releases are
skipped and are never overwritten; use a new version for changed downloads.
Adjust the workflow's branch filter if your default branch has another name.

Every push to `develop` (including a merged pull request, even without a
`pubspec.yaml` change) runs **Beta release** via `.github/workflows/beta.yml`.
It reuses the production pipeline, checks, signing secrets and downloads.
Beta releases are GitHub prereleases named/tagged `vMAJOR.MINOR.PATCH-beta`;
download filenames and versioned container tags also end the version in `-beta`.
Native app/installer versions remain numeric with the `pubspec.yaml` build
number. Manual runs of **Release** on `develop` also use the beta channel.

Production and beta runs share one concurrency group. Once a replacement beta's
checks and builds succeed, the workflow deletes all previous Quizmo `-beta`
releases (including drafts), their downloads and tags before creating the new
one, so at most one beta release exists, including for repeated builds of the
same version. A failed build leaves the previous beta intact; a publication
failure after cleanup may leave no published beta until a rerun succeeds.
Production publication removes only the beta with the same `MAJOR.MINOR.PATCH`,
regardless of build number. If that production version is already published,
beta publication is skipped and its matching beta is cleaned up instead.
Other production releases and unrelated prereleases are never deleted.

Beta containers use `VERSION-beta` and the rolling `beta` tag; they never move
production's `latest` tag or GitHub's latest-release selection. Old GHCR image
versions and workflow-run artifacts retain their existing retention behavior;
the single-beta policy applies to GitHub Releases and their tags/downloads.

Each release contains:

* `quizmo-VERSION-windows-x64-setup.exe`: Windows installer including all app
  files, shortcuts, uninstall support and Microsoft's Visual C++ runtime.
* `quizmo-VERSION-windows-x64-portable.zip`: complete app folder; extract it
  before launching `quizmo.exe`. Requires the Visual C++ x64 runtime separately.
* `quizmo-VERSION-android.apk`: signed universal APK for direct installation.
* `quizmo-VERSION-docker-linux-amd64.tar.gz`: backend and web clients; import
  using `docker load --input FILE`, then use `quizmo-server:VERSION`.
* `quizmo-VERSION-docker-deploy.zip`: Compose, Caddy, `.env.example` and setup
  instructions. Set `QUIZMO_IMAGE` and start with `--no-build`.
* `SHA256SUMS.txt`: download checksums.

The same version/build number from `pubspec.yaml` is embedded in the native
apps. CI artifacts are also available on the workflow run (14 days); the web
bundle is an internal build artifact (7 days). Release downloads remain until
the release is deleted. The Windows installer is **not code-signed**, so
SmartScreen may warn. Its bundled Microsoft runtime signature is verified in CI.

#### One-time GitHub setup

Enable GitHub Actions and allow workflows to create releases and packages
(`contents: write` is scoped to publication/cleanup and `packages: write` to
publication).
GHCR uses the built-in `GITHUB_TOKEN`; no extra registry password is needed.
The package is named `REPOSITORY-server`, with `VERSION` and `latest` tags.
New GHCR packages may be private: make the package public in its settings if
anonymous pulls are desired. For a pre-existing package, grant this repository
Actions access to it. The downloadable image archive works without GHCR access.
Flutter is pinned in the workflow; keep it compatible with the Dart constraint
in `pubspec.yaml` and the Dockerfile.

Create a dedicated Android release keystore **once**, or use the existing
release key if an APK has already been distributed. Keep a secure backup; APK
updates must use the same signing key and a higher build number. Never commit
the keystore or its passwords. Under **Settings → Secrets and variables →
Actions**, configure:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded complete JKS/keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing key alias |
| `ANDROID_KEY_PASSWORD` | Signing key password |

On Windows, `tool/create_android_signing.ps1` creates a self-signed RSA-3072
key (valid for 10,000 days), random password and a public certificate. It uses
the JDK's `keytool` and stores everything outside the repository in
`%USERPROFILE%\.quizmo\signing\android`, accessible to the current user and
SYSTEM only. It refuses to overwrite an existing directory: generate **once**,
not on every release. **This workspace's initial key has already been generated.**

```powershell
powershell -NoProfile -File tool/create_android_signing.ps1
```

The private `github-secrets.json` contains the exact values for the four
GitHub secrets above. Copy each value into the GitHub UI without its JSON
quotes, or use an authenticated GitHub CLI to upload them without displaying
the values (replace `OWNER/REPOSITORY`):

```powershell
powershell -NoProfile -File tool/publish_android_secrets.ps1 -Repository OWNER/REPOSITORY
```

Securely back up the **whole signing directory**, including its passwords.
Never upload it as a release asset or commit it. The public `.cer` alone
cannot sign updates. No purchased certificate or Play Store account is needed.

For an explicitly requested local release build with the **same key as CI**,
dot-source this in the PowerShell terminal that will run Flutter:

```powershell
. ./tool/use_android_signing.ps1
```

This only sets signing environment variables; it does not build or deploy.
Close the terminal afterwards to clear them. CI refuses to publish without
signing secrets and deletes the temporary keystore after building. Local
builds without these variables retain the existing debug-signing fallback.
Previously debug-signed installations cannot update to this new key without
uninstalling once (export quizzes first). Afterwards, local and GitHub APKs
can update each other if their application ID/signing key matches and their
build number increases. Windows remains unsigned; no Windows certificate or
Windows signing secrets are required.

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

## 7. Extending Quizmo

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

### LAN games via mDNS / DNS-SD

Native Android, iOS, macOS and Windows clients list LAN games on the join
screen. Starting a native host advertises `_quizmo._tcp` using the quiz name
and the actual bound `ServerEndpoint.port`. DNS-SD handles name collisions;
the list additionally displays the address and port, so identically named
hosts remain distinguishable. Select a **Reachable** entry, enter a player
name and continue to team selection. Reachability is checked against
`/api/health`; an unreachable entry cannot be selected.

The advertisement contains only a service name, type, hostname and port:
no TXT payload, invitation secrets, recovery/resume tokens, answers or quiz
content. Discovery is a convenience, not authentication. QR codes, links and
manual URLs remain available. Browser clients never invoke NSD and show the
manual-join fallback; Linux/headless Dart/Docker hosts do not advertise through
this Flutter plugin.

**Refresh LAN games** restarts discovery and clears cached entries. Lost-service
events remove entries immediately; a fresh browse every 20 seconds rechecks
reachability. Hosts that have been unreachable for a full refresh interval
are hidden even if the OS still returns cached DNS-SD records (allow another
2 seconds per address for probes). Native interface changes are checked every
3 seconds and restart discovery/registration. Backgrounding the app releases
discovery and advertisements; resuming recreates them if still needed. Leaving
the join screen or stopping/closing the host releases the respective resources.
Mobile operating systems may also suspend the server itself in the background.

Android declares `CHANGE_WIFI_MULTICAST_STATE`; Apple targets declare the
Bonjour service and local-network usage description, and macOS enables client
and server sandbox networking. Allow local-network access when prompted.
If no hosts appear, check Wi-Fi, permissions, VPN/firewall rules and client
isolation. mDNS needs UDP 5353 multicast; joining also needs the host TCP port
(normally 8080). Guest WLANs often block peer traffic. An empty list cannot
distinguish blocked multicast from a network with no active hosts; the UI
explains both and retains manual joining. Windows requires Windows 10 1903+
and an appropriate private-network firewall rule.

#### Multi-device LAN acceptance procedure

This is a manual hardware procedure, **not an automated or already completed
multi-device test**. Record OS/app versions, host/client devices, network and
results when running it.

1. Put two native hosts and two native clients on the same non-isolated LAN.
   Start hosts with the same quiz name (and different ports if on one machine).
   Verify both distinct address/port entries appear, show **Reachable**, and
   each selected host admits the intended player through team selection.
2. Stop one host; verify its entry disappears. Kill it without a graceful stop
   and verify stale entries clear after the next 20-second refresh. Block its
   TCP port and verify its entry becomes unselectable after a new probe.
3. Refresh repeatedly, leave/reopen the join screen and stop/start each host.
   Background/resume both roles. Verify no duplicate entries or accumulated
   native discovery/registration operations and no host advertisement while
   the host is stopped/backgrounded.
4. Move host/client between Wi-Fi networks, disconnect/reconnect Wi-Fi and
   toggle a VPN. Verify old entries clear and discovery/advertising recovers
   in the new LAN (3-second interface poll plus OS DNS-SD resolution). Repeat
   with multiple adapters and verify the reachable address is selected.
5. Deny/re-enable Apple local-network permission; block UDP 5353 while allowing
   the host TCP port; try isolated guest Wi-Fi. Verify understandable
   permission/network hints and successful manual/link/QR joining whenever
   unicast traffic is permitted.
6. Join via browser and test an unsupported platform: no native NSD calls,
   manual join and existing links/QR still work. Inspect DNS-SD records with
   `dns-sd -B _quizmo._tcp` and `dns-sd -L "<instance>" _quizmo._tcp local.`
   (or a LAN service browser): only public discovery
   metadata, no TXT secrets or solutions. Verify renaming/collision suffixes
   remain readable with long and non-ASCII quiz names.

Local regression coverage: `flutter test test/presentation/lan_discovery_test.dart test/presentation/nsd_lan_discovery_test.dart test/backend/lan_discovery_join_test.dart`
exercises lifecycle races, stale results, reachability, duplicates, fallback
platforms, host publication and a real HTTP/WebSocket join.

### Known gaps and deliberate decisions

* **Hand-written models:** `freezed` / `json_serializable` are declared in
  `pubspec.yaml`, but the models are hand written Dart 3 `sealed` classes with
  hand written JSON (exhaustive pattern matching, no generated files). The quiz
  file format is versioned explicitly (`schemaVersion`), see
  [quiz file format](quiz-file-format.md).
* **No user accounts:** access is controlled per session with an optional join
  code, host approval, a lobby lock and kick/ban ([Session access and
  moderation](hosting-guide.md#session-access-and-moderation)). Internet rooms add secret room
  links; private servers can add Basic Auth through the reverse proxy
  ([deploy/README.md](../deploy/README.md)). Bans cannot identify a person on a
  new browser or device.
* **Not built by the release pipeline:** macOS, iOS and ARM64 server images;
  there is no Linux desktop runner.
