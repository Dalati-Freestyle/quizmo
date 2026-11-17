# Internet hosting

Running Quizmo under your own domain, with browser storage, session lifetime
and security recommendations. Back to the [overview](../README.md).

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
Check `/api/health` from your monitor. The Docker build installs the official
Flutter Git tag on Ubuntu instead of depending on a third-party Flutter image.
`FLUTTER_VERSION` defaults to 3.47.5; CI passes the same version used by its
native builds as a Docker build argument. Pin Ubuntu images to reviewed digests
in production and update them regularly. Build this image on Linux (or a Linux
Docker builder).

Releases also provide a prebuilt Linux amd64 image as a `.tar.gz` download
and at `ghcr.io/OWNER/REPOSITORY-server:VERSION` (lowercase; exact reference
in the release notes). A deployment ZIP contains Compose, Caddy and setup
instructions. See [deploy/README.md](../deploy/README.md) for source-free setup,
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
and share the new link; use the explicit paused recovery flow above to retain
the most recently committed live match state.
Player refresh/reconnect and unattended TV reconnect retain their existing
behavior while the host room is alive. Rooms expire after 12 hours or 60 seconds
without a host heartbeat. Server restarts/deployments terminate active rooms.
Schedule deployments between games. Snapshots carry media references, not embedded
uploads. Released files are fetched through `/rooms/<room>/api/media/<sha256>`;
the host checks admission and visibility for each request. One file remains limited
to 20 MiB (about 27 MiB Base64 per relay envelope), below the unchanged 64 MiB
relay message limit. LAN mode remains independent of the relay.

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
URLs. The referrer policy (`strict-origin-when-cross-origin`) only ever sends
the origin to third parties, never the room path; OpenStreetMap tiles and the
YouTube embed require that origin and fail with `no-referrer`. TLS, CSP,
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
media sizes, concurrent users and outbound bandwidth. Each room allows at most
16 pending media requests, with a 20-second relay timeout. Players and TVs cache
verified media in a session-local, bounded in-memory LRU, so unchanged uploads are
not retransmitted for each snapshot. Downloads start only when the question or
solution is published, show progress, and offer retry after failure; future
questions and unrevealed solutions are never prefetched. Image resizing is
optional with a preview and explicit copy selection; originals remain the default.
See [media management](question-types-and-media.md) for limits and behavior.

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

---

