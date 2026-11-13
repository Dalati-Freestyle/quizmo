# Quizmo

A local-first, multi-device quiz platform. One device hosts the quiz; phones,
tablets, laptops and a TV browser join it. Quizmo runs in two modes:

* **LAN mode (native apps):** the host app runs an **embedded HTTP and
  WebSocket server** in its own process. Guests on the same network open the
  host's address or scan a QR code; no internet and no install are needed.
* **Internet mode (your domain):** the host plays in a browser under an HTTPS
  domain; players and TVs join an internet room through an invitation link,
  relayed by the Quizmo server (see [Internet hosting](docs/internet-hosting.md#internet-hosting-under-your-domain)).

Buzzer races are decided by **latency-compensated timestamps**, not by who sits
closest to the access point.

## Quick start

**Host (LAN):** install the app (Windows, Android, macOS; see
[Platforms](#platforms)), choose **Host a quiz**, pick a quiz from the library
(three example quizzes are included) and start hosting. Start the server in
the **Server** section; it shows the LAN address, alternative addresses and QR
codes for players and the TV. Optionally run the [**Tech check**](docs/hosting-guide.md#tech-check-before-the-game)
(dashboard app bar) before the first question, then **Start quiz**. After the
last question, **Quiz abschließen** (Finish quiz) shows players and the TV the
final page.

**Host (internet):** open `https://your-domain`, choose **Host a quiz**, select
a quiz and start hosting. Share the invitation link and its `/tv` link. Keep
the host tab open and the device awake.

**Player:** open the host's address (`http://<host>:8080`) or the invitation
link in any browser, or scan the QR code; enter a name and pick or create a
team. The native app finds LAN hosts automatically. Reloading the page keeps
you in the same game while the session runs.

**TV:** open `http://<host>:8080/tv` (or the invitation's `/tv` link) in a TV
browser, streaming stick or casted tab. The TV only watches: it shows the
lobby with join QR codes, questions, timers, standings and the final page.

**Create quizzes:** in the quiz library and editor (all question types and
formats, media, preview with bots), by importing a `*.quizmo.json` file, or
with an AI assistant using the AI quiz guide ([English](docs/ai-quiz-guide.en.md),
[German](docs/ai-quiz-guide.md)).

## Features

| Area | What exists today |
| --- | --- |
| Formats | Standard (solutions after each question or at the end), Jeopardy (board, Daily Double, steals, optional minus points), Pokerchips (stakes per team). |
| Question types | Multiple choice (single and multiple answers), buzzer, short answer (typo tolerance, optional manual grading), ordering, matching, estimation, true/false. Every type works in every format. See [question types and media](docs/question-types-and-media.md). |
| Media | Images, audio (playback limit), MP4, YouTube, code, OpenStreetMap maps on questions and solutions; uploads travel inside the quiz file. |
| Teams and scoring | Solo or teams, fixed points, speed bonus, buzzer ranking, manual grading, manual point changes for players or teams with a mandatory reason, undo via counter-corrections. |
| Hosting | Session access (join code, host approval, lobby lock, kick/ban), player merge, team assignment, recovery after a crash, customisable admin view (order, colours, optional sections hidden, every section collapsible with the state remembered, layout export and import), tech check before the game. |
| Players and TV | Timer on the player device, buzzer with clock sync, final page with standings, protocol view and PDF download; TV view with QR codes, guest Wi-Fi code, standings and end screen. |
| Reports | Final report with CSV export for the host; the game protocol (standings, all questions, answers and corrections with reasons) for players and TV at the end. |
| Editor | Quiz library (local), editor for every type and format, preview with simulated players, import/export as one `*.quizmo.json` file, example quizzes, AI quiz guide download in the settings. |

## Platforms

| Platform | Host (LAN server) | Player | TV | Notes |
| --- | --- | --- | --- | --- |
| Windows | Yes | Yes | Browser | Release: unsigned installer. YouTube opens in the default browser. |
| Android | Yes | Yes | Browser | Release: self-signed APK. Cannot read Wi-Fi passwords; import the QR screenshot of "Share Wi-Fi" instead. |
| macOS / iOS | Yes (from source) | Yes | Browser | No release builds are published. |
| Linux desktop | No (no Linux runner in this project) | Browser | Browser | Use the web player; the Linux server image is internet mode only. |
| Web browser | Internet mode only (no listening sockets in a browser) | Yes | Yes | The web player is served by the LAN host or the internet server. |
| Server (Docker, Linux amd64) | Internet relay | – | – | ARM64 images are not built. |

## LAN mode and internet mode

| Topic | LAN server (native host app) | Internet relay (your domain) |
| --- | --- | --- |
| Where the game runs | In the host app; guests connect directly to it. | In the host's browser tab; the server relays traffic between host, players and TVs. |
| Reachability | Same network only. Pick the address shown first; alternatives stay visible (see [“The address times out”](docs/developer-guide.md#331-the-address-times-out--picking-the-right-local-ip)). | Anyone with the invitation link. |
| Access control | Optional join code and host approval; anyone on the network can try to join. | Same session access, plus secret 192-bit room links; optional Basic Auth reverse proxy for private servers ([deploy/README.md](deploy/README.md)). |
| Origins / CORS | Permissive CORS (`*`) so browser players from another origin can join; the bundled player is same-origin. | Only `PUBLIC_ORIGIN` is accepted for browsers, CORS is not opened. |
| Transport security | Plain HTTP/WS in your network. | HTTPS/WSS via Caddy. |
| Session lifetime | As long as the host app runs. Saved-game recovery restores a crash. | Until the host tab closes or loses the server for 60 s; at most 12 h. Server restarts end rooms. |
| Reconnect | Players, TVs and the host recover automatically; the host can resume a saved game. | Players and TVs reconnect while the room lives; recovery creates a new room with a new link. |
| Guest Wi-Fi on the TV | Yes (stored encrypted on the host device). | Never forwarded through the relay. |

## Data, backups and known limits

* **Quiz library:** stored locally on the host device (native app storage, or
  the browser's storage for the origin/profile in internet mode). There is no
  account or cloud copy. **Back up by exporting** quizzes as `*.quizmo.json`
  (with embedded media) and import them elsewhere.
* **Running games:** the native host saves recovery checkpoints automatically
  ([Interrupted games and recovery](docs/hosting-guide.md#interrupted-games-and-recovery)). Players
  and TVs keep nothing permanently; the final protocol is gone after the host
  closed the session and the page is reloaded, so download the PDF first.
* **Media:** at most 20 MiB per upload, ten attachments per question, 90 MiB
  embedded media and 100 MiB per quiz file. Players and TVs download media only
  when a question or solution is published. YouTube and maps need internet.
* **Fairness:** timestamps are validated, but a modified client can still
  shift its timing within the allowed window; Quizmo is no anti-cheat system.
* **Quiz files:** newer apps read all older files; older apps ask for an update
  when a file needs a newer schema ([quiz file format](docs/quiz-file-format.md)).

## Documentation

* [Quiz file format and versions](docs/quiz-file-format.md)
* [Question types and media](docs/question-types-and-media.md)
* AI quiz guide: [English](docs/ai-quiz-guide.en.md), [German](docs/ai-quiz-guide.md)
* [Deployment of the internet server](deploy/README.md)
* [Hosting guide](docs/hosting-guide.md): tech check, session access and
  moderation, final report and protocol, connection status, example quizzes,
  AI quiz guide, editor preview, manual grading, reveal modes, recovery and
  manual corrections.
* [Internet hosting](docs/internet-hosting.md): your own domain, browser
  storage, session lifetime, security and infrastructure.
* [Developer guide](docs/developer-guide.md): architecture, folder structure,
  running from source, releases, design decisions, network contract and
  extending Quizmo; the binding rules are in [AGENTS.md](AGENTS.md).

