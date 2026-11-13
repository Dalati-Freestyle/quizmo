# Hosting guide

Everything the host needs during a game: checks before the start, session
access, reports, status displays, example quizzes, editor tools, grading,
reveal modes and recovery. Back to the [overview](../README.md).

## Tech check before the game

**Tech check** (dashboard app bar or the **Start quiz** section) checks the
host server (a timed, cancellable request to its own LAN address), the
reachability for guests, player connections, latency and clock sync against
thresholds (defaults: LAN good up to 150 ms round trip, error above 400 ms;
internet good up to 300 ms, error above 1000 ms; both adjustable under
**Settings > Hosting > Tech check thresholds**), the TV and
the quiz media (checksums of uploads, online media). **Start device test**
asks every player device to show a "Tap here" button; the check lists who
has not tapped yet; connected TVs show a notice and confirm automatically.
The test never touches the game and ends when the check
page is closed. Each finding is passed,
warning, error, not checkable or not required, with a next step. Missing data
is never shown as success, and a local server answer never counts as proof
that guests can reach the host. Warnings can be acknowledged; TV and media can
be marked as not required. **Copy report** contains no links, addresses, codes
or tokens; for problems it names the affected players or media. The check never changes the game.

Multi-device procedure: start the server, join with one phone over the QR code
and open the TV address on the TV; run the check and expect "passed" for
reachability, players and TV. Turn the phone's Wi-Fi off: within 15 seconds
the player check reports it by name. Use **Test playback** once on the host and
start one media question on the TV, because browsers often allow sound only
after a tap.

## Session access and moderation

The host's **Session access** panel controls both LAN and internet games. A
6–64-character join code and host approval are independently optional. New
players wait without receiving game snapshots or being added to a team until
approved. Closing the lobby rejects pending requests and blocks new admissions;
already admitted players can still resume with their existing identity and
secret token, without entering the code again. Reopening permits new requests.
Disabling approval does not silently approve requests already waiting.

**Remove** revokes the old resume token and removes the roster entry; joining
again requires a new admission. **Ban for this session** additionally rejects
the known identity throughout this session, including after server restarts or
saved-game recovery. Neither action identifies a person using another browser,
cleared browser storage or a different device: without accounts this cannot be
guaranteed. Use codes and host approval to control those new identities.

Spectators have a separate allow/deny switch. They use the same join code, but
never require individual approval and are independent of the player lobby lock.
Disabling spectators or changing/removing the code disconnects existing TVs;
they keep the last snapshot and retry, and can enter the current code on the TV.
Spectators never enter the roster or gain permission to submit answers.

Code guessing is limited to five failed attempts per socket and ten per minute
across the entire host hub, so opening another LAN or relay socket does not
reset the session-wide budget. Missing codes do not consume guesses. The shared
budget deliberately trades availability during guessing for brute-force
protection; after it is exhausted, wait one minute and reconnect.

Keep invitation links, codes and resume tokens confidential. They are never
written to the diagnostic feed. Protected REST snapshots and media also require
an admitted connection's read capability; its authority expires on disconnect,
removal or spectator revocation. Code hashes, access policy and banned
identities are saved in recovery schema 4 (schemas 1–3 remain readable).
Pending approvals and short-lived read capabilities are not restored: unadmitted
guests must request admission again. This changes session recovery, not the
portable quiz schema.

## Final report and CSV export

The last reveal does not end the game: players and TVs keep the solution of the
last question until the host presses **Quiz abschließen** (Finish quiz) in the
running round section. The flag icon in that section's header (**Quiz vorzeitig
beenden**) ends a game early after a confirmation; a running round is then
cancelled without scoring and reserved poker stakes go back to the teams.
Players then get the final page with their placement
(shown as a pop-up that fades out after a few seconds), the standings and the
game protocol as a view and PDF (emoji are drawn with the bundled Noto Emoji
font, in the browser in colour). Then the host dashboard shows **Final report** with the
authoritative final player/team standings, score progression, answers, accuracy
and response times by question/phase and participant. Manual point/chip
corrections and their reversals are reflected immediately; the CSV includes a
whitelisted correction audit trail. Historical progression records the totals
observed in each phase, not a reconstruction from correctness. Phase 0 is the
initial balance; the final standings are authoritative after roster changes.
Jeopardy keeps the picker's attempt and any steal as separate phases, labels
Daily Doubles and excludes participants who were not eligible. Poker reports
team chip balances and stakes; individual player points are **N/A**, skipped
zero-stake teams are not counted as wrong, and bankrupt practice answers are
explicitly marked. Standard team metrics aggregate actual member submissions;
board/Poker teammates who did not submit do not add another answer.

Hit rate means **fully correct answers / judged answers**; missing, ineligible
and unjudged submissions are excluded, not silently counted as wrong. Partial
accuracy is retained separately and does not count as a full hit (including
Poker's all-or-nothing payout). Practice answers contribute to accuracy but
never earn chips. Mean time includes recorded inputs only. Times are
milliseconds on the synchronized host answer clock, preserving accepted elapsed
times across recovery/timer restarts; Poker betting time is excluded and a steal
has its own clock. Buzzer times measure reaction, **not** the unrecorded spoken
answer. A disconnection flag means the host observed a disconnected participant
at some point in that phase; it does not assert why an answer is missing.

**CSV contract (report version 1):** UTF-8 with BOM, comma separator, CRLF
records, every field quoted, embedded quotes doubled, embedded newlines
preserved. Import it as comma-separated UTF-8 if a spreadsheet's locale expects
semicolons. Column names/order and machine-readable statuses do not depend on
the app language. Text beginning with a spreadsheet formula marker (also after
whitespace/control characters) is prefixed with an apostrophe; genuine numeric
negative scores stay numeric. Consumers must not remove this protection before
opening untrusted content in a spreadsheet.

| Columns | Meaning |
| --- | --- |
| `report_version`, `row_type`, `quiz`, `format`, `finished`, `history_complete` | Version and context; row types: `summary`, `answer`, `question_summary` (team), `progress`, `correction`. Formats: `standard`, `jeopardy`, `poker`. |
| `phase`, `question_id`, `question` | Chronological phase number and question identity/prompt; Jeopardy steals have another phase. |
| `entity_type`, `entity_id`, `name`, `team_id`, `team` | Player/team identity; answer rows identify the actual submitting player or the player without an answer. Historical names/membership are kept per phase. |
| `answer`, `status`, `accuracy_ratio` | Answer content; `correct`, `partial`, `incorrect`, `ungraded`, `noAnswer`, `notEligible`, `teamAnswered`. Team question summaries use `answered`, `noAnswer`, `notEligible`; correction rows use the correction kind. Accuracy is 0–1. |
| `response_time_ms`, `response_time_kind`, `connection` | Milliseconds; `buzzer_reaction` or `answer_submission`. Answer rows use `disconnection_observed` / `no_disconnection_observed`; summaries use `connected_at_end`, `disconnected_at_end` or `removed_from_roster` (no authoritative final score). |
| `practice_only`, `wager_chips`, `points_at_stake`, `steal`, `daily_double` | Booleans, Poker stake in chips, Jeopardy row value / Daily Double wager in points. |
| `score_unit`, `score` | `points` or `chips`; authoritative totals in summaries, observed cumulative balances in progression. |
| `evaluated_answers`, `fully_correct_answers`, `hit_rate_ratio`, `mean_response_time_ms` | Counts, 0–1 hit rate, mean milliseconds; team question summaries aggregate actual submissions for that phase. |
| `correction_id`, `reason`, `value_before`, `value_after`, `reverses_correction`, `score_delta` | Correction audit; before/after values are verdicts (0/1) for answer/buzzer corrections and points/chips for balance corrections; signed delta uses `score_unit`. |

`N/A` explicitly denotes unavailable or inapplicable values, never zero.
Choice/ordering answers contain JSON arrays of option IDs and labels; matching
answers contain JSON arrays of left/right IDs and labels (duplicate labels
remain distinguishable). Boolean answers use `true`/`false`; estimation answers
use a decimal point followed by the configured unit, if any. Spoken buzzer answers are not recorded. Report versioning
is separate from portable quiz-file versioning.

Report history is **host-only**: it is removed from player/TV snapshots and
never includes room credentials in the export. The CSV deliberately exports
only report fields, not complete game/checkpoint JSON, solution media, host
notes, invitation URLs, room codes, token hashes or resume tokens. Names and
answer text are still personal data: keep exports private and obtain any
necessary participant consent.

History is saved in the existing automatic recovery slot from #1, using recovery
schema **4** (schemas 1–3 remain readable). This is not a separate permanent
report library. On an older save, absent detail is explicitly marked incomplete;
it is never fabricated. Resetting the game clears report history in the next
successful recovery save. Deleting the saved game in recovery removes its
stored report from this device; a failed save/deletion is reported and the last
durable checkpoint may still exist. Downloaded/shared CSVs and external backups
must be deleted separately. No additional report data is uploaded.

## Connection and submission status

Players see text and icons for connecting, connected, reconnecting and a closed
room; status changes are announced as accessibility live regions. During a
network interruption the last board remains visible, but input is disabled.
The host roster explicitly labels connected/disconnected players. Silent sockets
are detected through periodic clock probes and a host-side inactivity timeout.
Returning from a long device lock checks socket freshness immediately and
rejoining starts with fresh clock samples.

Sending is not acceptance. An answer or buzzer press stays pending until the
host's committed snapshot confirms that player's submission for the current
round. This private confirmation contains no answer content, including in Poker.
After five seconds without confirmation the player shows an uncertain outcome
and rejoins to reconcile it. Reconnect and browser refresh restore the saved
identity and authoritative state while that session still exists. Unconfirmed
answers are **not queued or replayed**: if the host has no submission, the player
may retry manually while the round is open. The existing first-answer and
round/timestamp rules prevent duplicate scoring and reject late input.

An explicit host stop or a relay's closed-room response is terminal for players:
join a new room rather than waiting for reconnect. Timeouts and unreachable
hosts alone never prove that a room ended. TVs retain their existing indefinite
retry policy. This does not guarantee recovery of the host itself.

Automated fault-injection tests cover lost submissions, lost confirmations,
duplicate delivery, late input, clock changes after suspension, saved-identity
restoration and private Poker confirmations. Complement these with device
checks on Android/iOS and mobile browsers before release: switch Wi-Fi during
submission, lock/unlock for over 30 seconds, background/foreground the browser,
refresh after submitting, and explicitly stop the host. Check that no pending
input claims success, the roster detects the interruption, identity/scores
remain stable, and the same round's confirmed answer stays locked. Physical
device/network checks are not replaced by the automated suspension simulation.

## Example quizzes

Use **Settings > Advanced settings > Recreate example quizzes** to restore the
bundled Standard, Jeopardy and Poker examples. This replaces remaining unedited
defaults and restores deleted ones. Saving an example in the editor makes it a
normal quiz: it and all custom quizzes are preserved, even across repeated resets.
Default status is local library metadata, not part of exported quiz files.

## Create a quiz with an AI assistant

[`docs/ai-quiz-guide.en.md`](ai-quiz-guide.en.md) (English) and
[`docs/ai-quiz-guide.md`](ai-quiz-guide.md) (German) are a guide for any current AI
assistant (ChatGPT, Claude, Gemini, …). Load or paste it into a chat: the
assistant offers a fully automatic mode or walks you through format, teams,
timers, scoring and every question, and ends with one importable
`*.quizmo.json` file. Hosts can download the same file in the app language under
**Settings > Hosting > Create a quiz with AI**. It covers all formats and
question types of the current schema. Team colours are chosen by name from the
palette of the admin view, never by colour code. The assistant cannot embed
own images, audio or videos: add them in the editor afterwards.

## Editor preview

Choose **Preview quiz / Quiz-Vorschau** in the quiz editor to play the current
unsaved draft without saving it. The preview clones the draft into a separate
in-memory engine. It starts no server or internet room, writes no recovery
record or report, and never modifies the library or a real game's scores.
Invalid drafts show validation errors before the preview opens.

Switch between **Host**, **Player** and **TV**. The host uses the real round
controls; the player uses the real answer forms, buzzer and format controls.
Choose a test participant to answer manually. Player and TV snapshots use the
same redaction as real guests, including deferred results and solution media;
visible uploaded media remains available locally without a media server.

Add manual participants or bots, optionally in existing teams or their own test
teams. Each bot has a target success probability (0–100%) and an inclusive
minimum/maximum delay in milliseconds. Delays are drawn separately for actions,
including answers, buzzer presses and simulated host grading. The success rate
is a probability per answer, not an exact score for a short quiz. Correct bots
submit a full solution; incorrect bots choose a valid wrong choice, a nonmatching
text, a rotated ordering/matching, the opposite boolean or a zero-credit estimate.
Buzzer answers are judged with the configured probability. Manually graded bot
text is assessed automatically by the simulation; manual participants remain
under host control.

Jeopardy bots randomly choose an unplayed cell only on their turn, wait for host
confirmation, and randomly wager from 1 to the engine's Daily Double limit.
Poker bots reserve an affordable positive stake (zero if bankrupt), wait for
the host to close betting, then answer under the real one-answer-per-team and
practice-only rules. The host controls progression, buzzer reopening, round
completion and manual verdicts, just as in a real game.

The displayed **Seed** and the same sequence of inputs reproduce bot decisions
and virtual timestamps. Pause the simulation to enter inputs at exact times,
then use **Step +1 s**; pausing freezes engine timeouts as well as bot time.
**Automatic bots** suspends only bots, not the round clock. A new seed takes
effect with **Restart preview**, which resets scores, chips and all timers while
retaining test participants. **Replay round** restores the beginning of the
current question, including its initial roster, scores, board state and betting
phase; it restarts the seeded generator for that round. Leaving or restarting
disposes all simulation and engine timers. Bots are not available in real rooms.

## Manual short-answer grading

In the question editor, set a short-answer question's **Bewertung** to
**Manuell durch den Spielleiter** instead of **Automatisch**. The host sees
every submitted answer with a non-binding suggestion: exact solution match,
possible typo (using the configured edit tolerance), or a differing answer.
Mark each answer correct or incorrect; decisions can be changed until reveal.
Close submissions when ready, then finalize the assessment. Points and poker
payouts are booked only after all received answers have been judged. Speed and
rank bonuses still use the original, clock-adjusted submission timestamps.

The option works in Standard, Jeopardy (including steals and Daily Doubles) and
Pokerchips. Existing one-answer-per-team restrictions remain unchanged on boards
and in poker. Players and TVs do not receive host decisions before reveal.
Quiz schema 6 introduced this setting; schemas 1–5 remain importable and retain
automatic grading. Exports always use the latest schema.

## Standard quiz reveal modes

The standard quiz editor offers **Auflösung > Nach jeder Frage** (the default)
or **Am Quizende**. In the latter mode, the host still sees and grades answers
normally, but players and TVs receive no solutions, verdicts or standings until
the host finishes the quiz after the last question. This also applies to REST snapshots and uploaded
solution-media URLs, not just the visible controls.

At the end, players get the final page whose protocol lists every played
question, its solution, their submitted answer and assessment. The TV cycles through the solutions every 12 seconds; pause, previous and
next controls are available. The final standings are shown alongside the TV
overview. Reset clears the overview while retaining the configured reveal mode.
Jeopardy and Pokerchips keep their existing per-question reveal behavior.

Quiz schema 7 stores the reveal mode. All older schema versions remain readable,
retain per-question reveal and keep their question content, grading and media.

## Interrupted games and recovery

Quizmo saves a separate, versioned recovery record on engine transitions and
every second during answering/betting. On the next start it explicitly offers
**Continue saved game**, **Export private session report**, or **Discard**.
It never starts an old game silently. Leave the host dashboard to return to
that choice, including after a completed game. The quiz library is independent
and is not overwritten by recovery.

Recovery retains the quiz and uploaded question/solution media, players and
teams, accepted answers and manual verdicts, score history, completed questions,
deferred-reveal history, Jeopardy turns/steals/Daily Doubles and Pokerchips
balances/reservations/settlements. It loads **paused**, with everyone initially
offline and media paused. Start hosting, reconnect/reassign participants, then
explicitly choose **saved remaining time**, **a full timer restart**, or **a
soft timer** (no automatic timeout; the host ends the round). Downtime never
consumes the saved timer. A full restart retains earlier answers and their
original speed/rank scoring; it does not permit another answer. A pending
buzzer queue keeps its clock-adjusted ordering and is locked on continuation.
Closed/revealed rounds do not reopen. Timer overrides apply to the current
round only; new questions keep their configured timing rules.

Native recovery uses `recovery/session.json` and `recovery/quiz.json` under
`getApplicationSupportDirectory()` (the platform's per-user app-support
directory, not the quiz library). The immutable quiz/media document is written
once, flushed, and referenced by SHA-256. Small snapshots are flushed to
`session.pending` and atomically renamed over `session.json`. Interrupted
temporary files are never treated as successful snapshots. A file lock excludes
another host process; an in-process lock also excludes a second dashboard.
Browser recovery uses the origin/profile-local IndexedDB database
`quizmo-host-recovery-v1`, object store `checkpoints` (`current` and `quiz`).
Transactions commit the quiz and checkpoint together with strict durability;
Web Locks permit only one active host per origin. HTTPS (localhost excepted),
IndexedDB and Web Locks are required. No SharedPreferences/localStorage fallback
pretends to provide transactional host storage.

One latest committed session is retained, including finished games, until
explicit **Discard** with confirmation. This removes its recovery document,
quiz/media and server-side resume hashes, not the quiz library. Native lock
files contain no session data and may remain. Browser site-data deletion,
private-mode cleanup, OS storage removal, uninstall or disk failure can remove
recovery; this is not a cloud backup or a guarantee against hardware/power loss.
At interruption, the newest durable checkpoint is authoritative; a transition
whose write had not committed may need to be repeated.
Player/TV broadcasts, REST snapshots and solution-media access use the committed
state; clients are not told that an answer/result is accepted before its save.
Uncommitted host-side transitions can still be lost on abrupt termination.
Save failures display
an error, pause the engine and preserve the previous commit. Retry saving before
continuation. Corrupt/incomplete records are not overwritten or silently rolled
back; they require retry or explicit discard. Low-level permission/I/O failures
also prevent hosting until resolved.

The recovery envelope writes **schema 4**, independently of quiz schema 9
and the app version. It checks both the checkpoint and the referenced quiz,
requires complete/lossless fields and validates cross-references. Future recovery
schemas must retain a dedicated importer for each previous schema, migrate both
the game state and quiz references into the current model, and add fixed
compatibility fixtures. Unsupported newer schemas request a Quizmo update.
The existing quiz importers remain responsible for historical quiz definitions;
recovery writers write only the current recovery schema. Schema 1 records remain
readable and migrate with an empty correction ledger: historical manual decisions
are not invented by replaying scores. Schema 2 preserves the host-only correction
ledger, including counter-corrections and duplicate-request protection.
Schema 3 adds the session access settings (join code, approval, lobby lock,
bans) and schema 4 the per-question history of the final report; older
checkpoints restore with default access settings and an empty report history.

### Manual corrections and undo

The host dashboard's **Correction history** records each written-answer and
buzzer judgment, as well as explicit point/chip adjustments. Entries retain the
question and round opening time, player/team name, old/new value, timestamp and
optional reason. Selecting an unchanged written-answer verdict is a no-op.
The host can enter signed point/chip adjustments for the current round; poker
adjustments affect the team's chip balance, not an unused player point score.

**Undo** requires confirmation and appends a counter-correction; it never deletes
the original entry. Point/chip adjustments are reversed by their delta, preserving
later adjustments and updating the standings. Negative chip balances are rejected.
Written-answer judgments can be undone before settlement, provided no later
judgment of that answer is still effective. Buzzer undo restores the floor,
bookings and format bookkeeping only while no dependent round/board action has
occurred. Already spent chips, changed participants/teams, settled written answers
and dependent game actions block undo with an explanation. Use an explicit
point/chip adjustment when the original decision can no longer be safely undone.
Recovery clock changes can also invalidate round-bound judgment undo; financial
counter-bookings remain available after resuming. Reset clears scores and ledger.

The ledger and free-form reasons never travel to player or TV clients, even after
the results are revealed. Existing deferred-result/solution redaction still applies.

Resume tokens remain private in each player's browser profile/app storage; only
their SHA-256 verifiers are persisted by the host. A stable, **public** session
identifier in invitation links lets the same client find its saved identity
after a LAN address change or a new internet room. Internet reuse requires the
same origin. The player session now retains the complete room URL, not just its
origin. Old clients without a saved session identifier must be explicitly
reassigned after a room change. A different LAN browser origin, lost site data
or a replacement device also needs reassignment: while recovery is paused,
join as a new participant, compare its **verification ID** on the participant's
screen with the host's roster and confirm reassignment. This keeps the original
player ID, team, answers and score, and revokes the old credential. Never approve
by display name alone. Choose an existing team during recovery; creating an
extra team for an identity replacement would change format progress and is
therefore rejected until continuation. Ordinary reconnect within a live room still replaces
the stale socket using the original credential.

Recovery storage is **not encrypted by Quizmo**; protect the OS user/profile,
use device/disk encryption and do not copy private app-support/site data to
public shares. Browser scripts on the same origin can access its storage.
Tokens/hashes are never included in player/TV snapshots or logs. **Export private
session report** intentionally omits credentials, session IDs and room links,
but includes confidential answers, solutions, identities and media: it is not
a public/share-safe export, a portable recovery credential or an importable quiz.
Store it privately. Discard does not remotely erase a participant's own cached
credential; that credential becomes unusable at the deleted host.

### Internet room replacement

The relay remains ephemeral: host refresh/closure, expiry or relay restart
invalidates the old room and its player/TV links. Local recovery does **not**
recreate that room or recover its host socket. A restored browser host deliberately
creates a **new random room**, displays new invitation/TV links, and warns that
the previous links are invalid. Distribute the complete new links (including
the public session identifier); players reopen them in the same profile or use
verified host reassignment. TVs open the new `/tv` link; they remain read-only
and keep reconnecting to a live room, but cannot discover a replacement room.
Loss of the relay while the host tab is still alive also pauses the engine;
restart hosting, redistribute links, and confirm the timer rule. There is no
cross-device quiz sync (#11), relay-side durable engine or multi-server failover.

Recovery tests run with `flutter test`. The renderer-independent browser check
is `test/browser/recovery_store_check.dart`: compile it with `dart compile js`
to a temporary `recovery_store_check.js`, place
`test/browser/recovery_store_check.html` beside it, and serve that directory on
localhost/HTTPS. Its page must display `PASS` for IndexedDB commit/abort,
media retention, explicit deletion and exclusive Web Locks. This check does not
need Flutter renderer assets or an application web build.

