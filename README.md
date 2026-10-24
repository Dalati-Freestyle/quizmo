# Quizmo

Quizmo can also be hosted under an HTTPS domain. Hosts create and edit quizzes
in their browser; players and read-only TVs join an internet room through an
invitation link. Native apps still support the existing standalone LAN server.

## Internet hosting under your domain

Point your domain's DNS A/AAAA records at the server (only publish AAAA if IPv6
really works). Install Docker Engine with Compose. Copy
`deploy/.env.example` to `deploy/.env`, set `QUIZMO_DOMAIN` to your purchased
domain without a scheme or path, then run from the repository root:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d --build
docker compose --env-file deploy/.env -f deploy/compose.yaml logs -f
```

Open `https://your-domain`, choose **Host a quiz**, create/select a quiz, and
start hosting in the dashboard. Share the invitation
`https://your-domain/rooms/<random-invitation>` with players. Share its `/tv`
URL with a TV browser. Players can also paste the full room link into a native
Quizmo app. Connections use WSS, and clock synchronization measures the
browser host's clock through the relay, including the complete internet path.

Caddy obtains and renews TLS certificates and redirects HTTP to HTTPS. Only
ports 80/443 are published; the backend is on the Docker network. Preserve the
Caddy volumes containing certificates. The app runs without root, a writable
root filesystem or Linux capabilities, with CPU, memory and process limits.
Check `/api/health` from your monitor. The Docker build uses Flutter 3.47.5;
pin both build/runtime images to reviewed digests in production and update
them regularly. Build this image on Linux (or a Linux Docker builder).

Releases also provide a prebuilt Linux amd64 image as a `.tar.gz` download
and at `ghcr.io/OWNER/REPOSITORY-server:VERSION` (lowercase; exact reference
in the release notes). A deployment ZIP contains Compose, Caddy and setup
instructions. See [deploy/README.md](deploy/README.md) for source-free setup,
LAN/HTTPS configuration and image import. ARM64 is not currently built.

For a development run without Docker:

```powershell
dart run tool/bundle_web_client.dart
$env:PUBLIC_ORIGIN = 'http://localhost:8080'
dart run bin/server.dart
```

Open exactly that origin. HTTP hosting is accepted only on localhost/127.0.0.1.
For a standalone executable, run `dart pub get` inside `server/`, then compile
from that same directory with
`dart compile exe bin/server.dart -o ../build/quizmo-server`
(on Windows append `.exe`). This separate pure Dart dependency graph avoids
Flutter plugin build hooks; it shares the backend sources without duplicating
implementation. The Docker build uses this graph too.
For your own reverse proxy set `PUBLIC_ORIGIN=https://your-domain`, `PORT`
(default 8080), `WEB_ROOT` (default `build/web`), and optionally `BIND_ADDRESS`
(default 127.0.0.1). Forward both normal HTTP requests and WebSocket upgrades
without removing room paths. Copy the security headers from `deploy/Caddyfile`,
including CSP and HSTS. Deploy at the domain root, not in a subdirectory.

### Browser storage, exports and session lifetime

The quiz library, including uploaded media, is stored locally in the browser,
scoped to that origin and browser profile. It is not a server-side account or
cloud backup. Browser storage quotas apply; private browsing, clearing site
data, a different domain/profile or a different device do not share that
library. Storage failures are reported by the library. Export important quizzes
as `*.quizmo.json` (including embedded media) and import them on another device.

For a controlled exit, use **Seite verlassen** in the quiz library. It asks
whether to export and offers a download for each quiz. When closing/reloading
the tab with custom quizzes, Quizmo requests the browser's native leave
confirmation. Browsers prohibit customized unload dialogs and downloads during
unload: choose **stay/cancel**, then export from the library. Browsers require
prior interaction for this confirmation; mobile task termination/crashes may
skip it entirely. Saved quizzes remain locally stored after a normal close.

Keep the host tab open and the device awake. The browser owns the existing
game engine; the relay transfers player traffic and redacted snapshots. Closing,
reloading or losing the host connection ends the internet room. Restart hosting
and share the new link; quizzes remain saved, live match state does not persist.
Player refresh/reconnect and unattended TV reconnect retain their existing
behavior while the host room is alive. Rooms expire after 12 hours or 60 seconds
without a host heartbeat. Server restarts/deployments terminate active rooms.
Schedule deployments between games. Uploaded media in a single outgoing
snapshot must fit the relay's 64 MiB message limit; use smaller files or remote
YouTube references for large videos. LAN mode remains independent of the relay.

### Security and infrastructure recommendations

The relay isolates rooms with cryptographically random 192-bit invitations.
Only the dedicated host socket can send messages to a particular player; guest
frames cannot act as host control envelopes or impersonate other connections.
The existing hub validates player identities and resume tokens, redacts solutions
and secret format data, restricts submissions to joined players, and now rejects
timestamps outside the round or an implausible time window. This preserves NTP
ordering; a modified client can still falsify timings within that window, so this
is not an anti-cheat guarantee against hostile client software.

Browser origins are checked against the explicit `PUBLIC_ORIGIN`, including
WebSocket upgrades; cross-origin hosting is rejected and CORS is not opened.
Native players may omit Origin. Origin is a browser security measure, not
authentication: native tools can forge it. Hosting is intentionally public, with
no account system. Treat invitations as access secrets: anyone with the link can
join/watch. Do not publish them, include them in analytics, or log full room
URLs. Referrer suppression reduces accidental link disclosure. TLS, CSP,
anti-framing, MIME sniffing protection and restrictive device permissions are
provided by the deployment configuration without disabling supported media.

Application limits: 128 rooms, 128 connections per room, 256 registered players
per game (including offline players; existing participants can resume), a
15-second timeout for sockets that never join/watch/request a lobby, 60 guest frames/second,
64 KiB guest frames, 2048 host frames/second and 64 MiB host envelopes. Excessive
or binary frames close the connection. HTTP traffic has a global 1000 requests/
second limit. Upgrade quotas are 20 host attempts and 300 guest attempts/minute
per direct peer, with bounded quota bookkeeping. Behind the included proxy,
these quotas apply to its shared address; the app deliberately does not trust
client-supplied forwarding headers. Tune capacity only after measuring memory,
media sizes, concurrent users and outbound bandwidth. Large uploads are repeated
in snapshots, so use small media for internet sessions.

Recommended before exposing a public installation:

- Put a DDoS-protected reverse proxy/CDN/WAF in front of the domain with
  WebSocket support. Enable provider network-level DDoS protection: application
  limits cannot protect saturated bandwidth or floods before the Dart handler.
- Enforce per-client IP connection/upgrade quotas and request rate limits at the
  trusted edge. Add a bot challenge/access gateway for host creation if abuse
  becomes relevant. The included Caddy config does not provide a WAF or per-IP
  rate limiting. Use a WebSocket-aware gateway to cap frame sizes and traffic:
  ordinary proxy HTTP body limits do not limit upgraded WebSocket messages,
  which Dart must assemble before the application can reject them.
- Restrict the origin firewall to the trusted proxy/provider when using a CDN;
  expose no backend, Docker daemon, SSH passwords or debug/VM-service ports.
  Use key-based SSH and firewall administrative access. Trust forwarded client
  addresses only from explicitly configured proxy ranges.
- Use long-lived WebSocket support/timeouts, monitor connections, room count,
  memory, CPU, bandwidth, TLS renewal and health, and alert on spikes/errors.
  Avoid logging room links, player resume tokens, quiz content or full frames.
- Patch OS, Docker, Dart/Flutter dependencies and proxy regularly; scan images
  and dependencies. Keep TLS private keys in protected volumes and use automated
  backups for operational configuration. Users must back up their quiz exports.
- Run one relay instance for this configuration. Rooms live in process memory;
  multiple replicas require routing each room's host and guests to the same
  process or a shared room broker. A generic round-robin load balancer will not
  work. Start with a small instance and load-test your intended audience.

The Internet relay has end-to-end tests for room isolation, lobby/join and clock
sync, spectator redaction, rejected origins, oversized guest messages and room
cleanup. A deployment still needs testing with your actual DNS, TLS, proxy and
two independent internet connections.

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
(`contents: write` and `packages: write` are scoped to the publishing job).
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

