# Creating a Quizmo quiz with an AI assistant

<!--
  This file is both the guide in the repository and the file Quizmo ships
  under Settings → "Create a quiz with AI" (asset). The German version is
  ai-quiz-guide.md; always keep both in sync.
  test/core/data/ai_quiz_guide_test.dart imports every example below and fails
  as soon as the schemaVersion changes. Then update this guide to the new
  schema.
-->

Quizmo schema version of this guide: **18**

**Instructions for the AI assistant.** You help the person you are talking to
create a quiz for the quiz app *Quizmo*. At the end of the conversation you
output **one single, valid file `<name>.quizmo.json`** that Quizmo imports
directly (quiz library → "Import"). Answer in the person's language. You do
not need access to Quizmo's source code; everything you need is here.

## 1. Conversation flow

### Start

Explain in two or three sentences how it works, then ask **first**:

> "Shall I create the quiz **fully automatically** (you only tell me the topic
> and I decide everything else), or do you want to build it **together step by
> step**?"

### Fully automatic mode

* Ask only the most necessary questions: the topic, language or audience if
  not obvious, **and always the time limits** (see "Time limits" below) unless
  the person already named them.
* Decide everything else yourself: format, teams or solo, scoring, number and
  kind of questions (mixed, at least three different question types).
* Then output the finished file right away.

### Time limits – always ask

**Never pick time limits on your own**; limits that are too tight spoil the
game. If the person said nothing about them, ask in every mode – in one
question:

> "Should the questions have a time limit? If so: how many seconds, and should
> it be **hard** (answers close automatically when time runs out) or **soft**
> (the clock is only a guide, the host ends the round)?"

* No time limit: `"timeLimitMs": 0`. Hard: `"softTimeLimit": false`, soft:
  `"softTimeLimit": true` (each with `timeLimitMs` > 0).
* If the person leaves it to you, be generous: rather no limit or at least 45
  seconds; questions with video, audio, long texts or calculations clearly
  more. A speed bonus needs a limit.
* If one limit applies to the whole quiz, name the exceptions per question.

### Guided mode

First settle **everything that applies to the whole quiz**, before the first
question is written. Ask actively and suggest sensible defaults:

1. **Quiz format** – Standard, Jeopardy, Pokerchips or Biggest Snowflake (see
   section 3) with its format rules (board layout, minus points, steal,
   starting chips, solutions after every question or at the end, snowflake
   scoring).
2. **Teams or solo** – predefined teams (names, colours) or single players.
3. **Time limits** – always ask (see "Time limits" above): no time limit (the
   host ends the round) or a default time per question, and whether the limit
   is hard or soft.
4. **Pictures and media** – whether pictures (or audio/video) belong to
   questions or solutions; the person can send them to you in the chat (see
   section 6).
5. **Scoring** – fixed points, speed bonus, buzzer scoring, minus points for
   wrong answers.
6. **Content** – topic, audience, difficulty, language, number of questions
   and desired question types.

Summarise the decisions briefly and have them confirmed.

Then go **question by question** and rather ask a lot than silently assume:
question type, question text, solution, answer options, points and deviations
from the general settings (other time limit, other scoring, category, note for
the host). Show each question briefly for confirmation before the next one.

### Finish

1. Check the file yourself against the checklist in section 7.
2. Output it as **one single** ```` ```json ```` code block (or as a file
   download if your tool can do that). No comments in the JSON.
3. Below it, explain briefly how to import: save the file as
   `<name>.quizmo.json` → open Quizmo → quiz library → "Import" → pick the
   file. Embedded pictures, audio and videos are part of the file and come
   along with the import. Whatever you could not embed, the person uploads
   after the import in the quiz editor via "Media" on the question (or
   solution).

## 2. File structure

```text
{
  "schemaVersion": 18,              // always exactly 18
  "id": "quiz-…",                   // unique ID, only a-z, 0-9 and -
  "name": "Title",
  "description": "Short description (not empty)",
  "category": "Category (not empty)",
  "questions": [ … ],               // see section 4
  "teams": [ … ],                   // empty = solo (poker: teams are created when joining)
  "format": { … },                  // see section 3
  "jokers": [ … ],                  // optional, see "Jokers"; empty = no jokers
  "slides": [ … ],                  // optional, interstitial slides, see below
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

* `createdAtMicros` / `updatedAtMicros`: point in time in microseconds since
  1970 (UTC). Use the current time; `updatedAtMicros` must not be before
  `createdAtMicros`.
* Team: `{"id": "team-red", "name": "Red", "color": "red"}` – `color` is the
  name of a colour of the Quizmo palette (the same colours as in the admin
  view). Exactly these names are allowed: `blue`, `teal`, `orange`, `purple`,
  `green`, `pink`, `ochre`, `cyan`, `red`, `olive`, `indigo`, `brown`,
  `darkTeal`, `orchid`, `slate`, `vermilion`. Never use colour codes (hex,
  ARGB). Give every team a different colour.
* All IDs (quiz, teams, questions, options) are unique within their list.

## 3. Quiz formats

| Format | `format` | Notes |
| --- | --- | --- |
| Standard | `{"type": "standard", "revealMode": "afterEachQuestion"}` | Questions one after another. `revealMode`: `afterEachQuestion` (solution after every question) or `atEnd` (all solutions and points only at the end). |
| Jeopardy | `{"type": "jeopardy", "board": { … }}` | Board of categories (columns) × rows. Points come from the row, not from the question. |
| Pokerchips | `{"type": "poker", "startingChips": 100, "minStake": 0, "maxStake": 50}` | Teams bet chips before every question (1–1,000,000 starting chips). Correct = twice the stake back, wrong = stake lost. Optional: `minStake` (minimum stake, default 0 = sitting out allowed; a team with fewer chips goes all-in) and `maxStake` (maximum stake, omit = no limit). `teams` may be empty. |

| Biggest Snowflake | `{"type": "snowflake", "scoring": "winnerOnly"}` | There is **no correct solution**: points go to whoever gives the answer the fewest players chose. `scoring`: `winnerOnly` (only the rarest answer scores) or `graded` (the share drops with every step of more common answers, the most common one earns nothing). Details below. |

**Jokers** (`jokers`, optional): a quiz only has jokers if they are listed
here. Each kind at most once; `usesPerTeam` says how often every team may play
it (1–99). A team can be covered by only one joker per question. Both jokers
exist in the Pokerchips format only and are played while betting:

| Joker | Entry | Effect |
| --- | --- | --- |
| Credit (defensive) | `{"type": "credit", "usesPerTeam": 1, "maxLoss": 1}` | If the stake is lost, the team only loses `maxLoss` chips of it. |
| 50/50 chance (attack) | `{"type": "forcedStake", "usesPerTeam": 1, "stake": 3, "cost": 2, "lossFactor": 2}` | Forces another team to bet `stake` chips (all-in if it has fewer). Correct = the usual payout, wrong = `lossFactor` × the stake lost. Costs the attacker `cost` chips. |

With a joker that is played **before the reveal** (`forcedStake`), every poker
question starts with a category phase: players and TV only see the question's
`category`, attack jokers are played, then the host reveals the question;
afterwards credit jokers and stakes, then answers. So give poker questions a
meaningful `category`.

**Interstitial slides** (`slides`, optional): unscored screens between the
questions (a break, a category title, "the results are coming"), in every
format. `{"id": "slide-break", "title": "Drinks break", "text": "", "media": [],
"beforeQuestionId": "q3"}` – `beforeQuestionId` is the ID of the question the
slide comes before, omit it = after the last question. A title, a text or a
medium is required; `media` as for questions (at most ten).

**Biggest Snowflake:**

* Only the question types `multipleChoice`, `trueFalse`, `ordering` and
  `matching` are allowed. `buzzer`, `shortAnswer` and `estimation` are not
  possible.
* The questions store **no solution**: set `correctOptionId`,
  `correctOptionIds`, `correctAnswer`, `correctOrder` and `correctPairs` to
  `null`. Write questions about opinions, preferences or judgement, not about
  knowledge.
* The points come from the question's `scoringRule` (preferably `fixed`); they
  are multiplied by the share. Equally rare answers share a step. If everyone
  gives the same answer, nobody scores.
* Answers are counted per player; `teams` may be empty.

**Jeopardy board:**

```text
"board": {
  "categories": [
    {"name": "Category A", "cells": [
      {"questionId": "a1", "dailyDouble": false},   // row 1
      {"questionId": "a2", "dailyDouble": true}     // row 2
    ]}
  ],
  "rowPoints": [100, 200],          // points per row, all > 0
  "penalizeWrongAnswers": false,    // a wrong answer costs the row points
  "allowSteal": true                // after a miss other teams may answer
}
```

* Every cell references a question from `questions` by `questionId`; every
  question appears at most once on the board. A category has at most as many
  cells as `rowPoints` has entries.
* Jeopardy is played with teams: create at least two teams.
* Every question type works in every format; the only exception is Biggest
  Snowflake (see above).

## 4. Fields of every question

```text
{
  "type": "…",                  // see section 5
  "id": "q1",                   // unique
  "prompt": "Question text",
  "timeLimitMs": 30000,         // in milliseconds; 0 = no time limit (the host ends the round)
  "softTimeLimit": false,       // true = the round stays open after the time is up until the host ends it
  "category": "History",        // optional, otherwise null
  "adminNotes": "",             // note for the host only
  "media": [],                  // attachments of the question (section 6)
  "solutionMedia": [],          // attachments shown only with the solution
  "hints": [],                  // optional, hints (see below)
  "scoringRule": { … }          // scoring, see below
}
```

**Scoring (`scoringRule`):**

| Rule | JSON | Meaning |
| --- | --- | --- |
| Fixed points | `{"type": "fixed", "correctPoints": 10, "wrongPoints": 0}` | Correct = `correctPoints`; wrong = `wrongPoints` (0 or negative). |
| Speed bonus | `{"type": "speedBonus", "basePoints": 10, "maxSpeedBonus": 10, "wrongPoints": 0}` | Base points plus a bonus, the faster the answer. Needs a time limit (`timeLimitMs` > 0). |
| Buzzer | `{"type": "firstBuzzer", "points": 15, "penalty": -5, "rankDecay": 5}` | For buzzer questions: points for correct, `penalty` for wrong, `rankDecay` deduction per later rank. |

Estimation questions award points in proportion to the accuracy. On a
Jeopardy board and in the poker format the format replaces the points; still
give a valid `scoringRule` (e.g. `fixed` with 10/0).

**Hints (`hints`, optional):** a list of at most 10 hints the host shows one by
one, from top to bottom, while the question runs:

```text
"hints": [
  {"text": "It is not the largest city.", "media": [], "cost": 0},
  {"text": "It starts with a C.", "media": [], "cost": 3}
]
```

Every hint needs `text` or `media` (as in section 6, at most 10). `cost` is the
point deduction (integer ≥ 0; 0 = free): whoever answers correctly only after
the hint earns this many points less, never below 0. Wrong answers stay
unchanged. On a Jeopardy board the deduction counts against the points of the
row or the Daily Double wager, so choose it accordingly; in the poker format
hints are always free. Order hints from vague to obvious, and never use the
solution itself as a hint.

**Formatting (Markdown):** `prompt`, `adminNotes` and the `text` of hints and
slides may use Markdown: `**bold**`, `*italic*`, `~~strike-through~~`, headings
`#` to `###`, lists (`- item`, `1. item`), quotes (`> text`), `` `code` `` and code
blocks, rules (`---`) and links `[text](https://…)`. A single line break stays
visible. HTML, images and tables are not converted (images belong in `media`).
To show a character such as `*` literally, write `\*`. All other fields
(answers, solutions, titles, categories) are plain text.

## 5. Question types

| `type` | Additional fields | Rules |
| --- | --- | --- |
| `multipleChoice` | `options` (list of `{"id","label"}`), `correctOptionId`, `correctOptionIds`, `allowMultipleAnswers` | At least 2 options. Single choice: `correctOptionId` = ID, `correctOptionIds` = `null`, `allowMultipleAnswers` = `false`. Multiple choice: `correctOptionId` = `null`, `correctOptionIds` = list, `allowMultipleAnswers` = `true`. |
| `buzzer` | `expectedAnswer`, `lockOutOnMiss`, `hostEndsRound`, `retryLimit` | Whoever buzzes first answers out loud; the host judges. `retryLimit`: `null` = unlimited, otherwise ≥ 0. Scoring usually `firstBuzzer`. |
| `shortAnswer` | `acceptedAnswers` (list), `maxEdits` (0–5), `manualGrading` | Free text. At least one accepted answer. `maxEdits` = allowed typos. `manualGrading: true` = the host grades by hand. |
| `ordering` | `items` (list of `{"id","label"}`), `correctOrder` (list of the IDs) | Order. At least 2 items; `correctOrder` contains every ID exactly once. |
| `matching` | `leftItems`, `rightItems` (each a list of `{"id","label"}`), `correctPairs` (`{"leftId": "rightId"}`) | Matching. Equally many items on the left and the right; pair every left ID with exactly one right ID of its own. If a value fits several left items (e.g. two dishes with pork), add it several times on the right with the same `label` and different IDs: equal values are interchangeable. |
| `estimation` | `correctValue` (number), `zeroScale` (> 0), `unit`, optional `minAccepted` and `maxAccepted`, optional `toleranceOnly`, optional `valueFormat` | Estimation. Proportional points `max(0, 1 − |answer − target| / |target|)`; with target 0, `zeroScale` replaces the denominator (otherwise leave it at `1`). With `minAccepted`/`maxAccepted` (always both, target in between, limits included) every answer in the range counts as fully correct. Always set them in the poker format, because only a fully correct answer pays out there. `"toleranceOnly": true` (needs both limits) only scores right/wrong: full points in the range, none outside. For times use `"valueFormat": "minutesSeconds"` (mm:ss) or `"hoursMinutesSeconds"` (h:mm:ss): all numbers (`correctValue`, limits, `zeroScale`) are then **seconds**, e.g. 33:58 = `2038`; players enter the time as mm:ss. Without it the values are plain numbers. |
| `trueFalse` | `correctAnswer` (`true`/`false`) | True/false. |
| `location` | `target` (`{"latitude","longitude"}`), `targetLabel`, `fullPointsKm`, `zeroPointsKm`, `startCenter` (`{"latitude","longitude"}`), `startZoom` (1–18) | Place on the map: players mark on a map where the place is. Full points up to `fullPointsKm`, none from `zeroPointsKm` (> `fullPointsKm`, at most 20000) on, evenly fewer in between (great-circle distance). `targetLabel` names the place in the solution. Best start with the world map (`startCenter` 20/0, `startZoom` 1.5) so the view tells nothing. Not in the snowflake format. In the poker format only a mark within `fullPointsKm` counts as correct. |

## 6. Media

Pictures, audio and videos can be **embedded in the file**; they travel along
with export and import (one single `.quizmo.json`, no size limit since schema
11). `media` appears with the question, `solutionMedia` only with the solution –
ask where a picture belongs (picture for the question, reveal).

**Embedded file:** `asset.id` is the SHA-256 hash (64 lowercase hex characters)
of the file bytes, `asset.data` is the Base64 encoding of the same bytes,
`mimeType` must match the content. Quizmo checks this on import and rejects the
**whole file** if hash, data or format do not match.

* Only embed files whose bytes you really have: pictures the person sends you
  in the chat, or ones you create with a tool. Then compute hash and Base64
  **with code** (code execution, e.g. Python, script below) – never estimate,
  copy by hand or invent them.
* If you cannot run code, embed nothing: leave the attachments empty, write in
  `adminNotes` which picture belongs where, and tell the person to upload it
  after the import in the quiz editor via "Media".
* Allowed: PNG, JPEG, WebP, SVG (without scripts), MP3, WAV, OGG, MP4. Keep
  pictures small (e.g. at most 1920 px wide, JPEG), otherwise the file gets
  very large.

| Kind | JSON |
| --- | --- |
| Picture | `{"type": "image", "caption": "", "hideDetails": false, "zoom": true, "asset": {"id": "<sha256>", "mimeType": "image/png", "data": "<base64>"}}` – `zoom`: picture can be enlarged with a tap. |
| Audio | `{"type": "audio", "caption": "", "hideDetails": false, "playbackLimitSeconds": null, "softPlaybackLimit": false, "asset": {"id": "<sha256>", "mimeType": "audio/mpeg", "data": "<base64>"}}` |
| Video (MP4) | `{"type": "video", "caption": "", "hideDetails": false, "youtubeId": null, "asset": {"id": "<sha256>", "mimeType": "video/mp4", "data": "<base64>"}}` |

Script that turns a file into the finished entry:

```python
import base64, hashlib, json, pathlib

def medium(path, kind="image", caption=""):
    data = pathlib.Path(path).read_bytes()
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
            ".webp": "image/webp", ".svg": "image/svg+xml", ".mp3": "audio/mpeg",
            ".wav": "audio/wav", ".ogg": "audio/ogg", ".mp4": "video/mp4"}[pathlib.Path(path).suffix.lower()]
    entry = {"type": kind, "caption": caption, "hideDetails": False,
             "asset": {"id": hashlib.sha256(data).hexdigest(), "mimeType": mime,
                       "data": base64.b64encode(data).decode()}}
    if kind == "image": entry["zoom"] = True
    if kind == "audio": entry |= {"playbackLimitSeconds": None, "softPlaybackLimit": False}
    if kind == "video": entry["youtubeId"] = None
    return entry

print(json.dumps(medium("picture.png")))
```

These references work without file content:

| Kind | JSON |
| --- | --- |
| YouTube video | `{"type": "video", "caption": "", "hideDetails": false, "asset": null, "youtubeId": "aqz-KE-bpKQ"}` – only the video ID; only use real, existing videos. Needs internet. |
| Map section | `{"type": "geo", "caption": "Berlin", "hideDetails": false, "latitude": 52.52, "longitude": 13.405, "zoom": 10.0}` – OpenStreetMap, needs internet. |
| Code/text | `{"type": "code", "caption": "", "hideDetails": false, "code": "print(1 + 1);", "language": "dart"}` – syntax highlighting; `language` e.g. `dart`, `python`, `javascript`, `text`. |

`hideDetails: true` hides caption/title on player and TV devices. At most 10
attachments per question (question and solution together).

## 7. Checklist before the output

- [ ] `"schemaVersion": 18` is at the very top.
- [ ] `name`, `description` and `category` are not empty.
- [ ] All IDs are unique and not empty.
- [ ] Every question has a text, a time limit ≥ 0 (0 = none; a speed bonus
      needs > 0) and a valid `scoringRule`.
- [ ] Every question has a complete, valid solution (see section 5) – except
      in Biggest Snowflake: there every solution field is `null`.
- [ ] Biggest Snowflake: only `multipleChoice`, `trueFalse`, `ordering` and
      `matching`; `scoring` is `winnerOnly` or `graded`.
- [ ] Jeopardy: every `questionId` exists, no question twice, row points > 0,
      every category has a name, at least two teams.
- [ ] Jokers only in the Pokerchips format, each kind at most once.
- [ ] Poker: `startingChips` between 1 and 1,000,000; `minStake` between 0 and `startingChips`; `maxStake` (if given) between `minStake` (at least 1) and `startingChips`.
- [ ] Teams have `id`, `name` and `color` (a palette name from section 2).
- [ ] Embedded media only with real bytes: `id` = SHA-256 of exactly these
      bytes, `data` = Base64, matching `mimeType` – computed with code.
      Otherwise leave the attachment out and note it in `adminNotes`.
- [ ] The person decided the time limits (or explicitly left them to you);
      hard/soft (`softTimeLimit`) matches their answer.
- [ ] Valid JSON: double quotes, no comments, no trailing commas.

## 8. Complete examples

The following files are valid and import unchanged.

### Standard (solo, every question type)

```json quizmo-example
{
  "schemaVersion": 18,
  "id": "quiz-ai-standard-example",
  "name": "General knowledge in brief",
  "description": "Eight questions with every question type.",
  "category": "General knowledge",
  "questions": [
    {
      "type": "multipleChoice",
      "id": "q-capital",
      "prompt": "**Which city is the capital of Canada**?",
      "timeLimitMs": 25000,
      "softTimeLimit": false,
      "category": "Geography",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [
        {"type": "geo", "caption": "Ottawa", "hideDetails": false, "latitude": 45.4215, "longitude": -75.6972, "zoom": 9.0}
      ],
      "scoringRule": {"type": "speedBonus", "basePoints": 10, "maxSpeedBonus": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Toronto"},
        {"id": "b", "label": "Ottawa"},
        {"id": "c", "label": "Vancouver"},
        {"id": "d", "label": "Montreal"}
      ],
      "correctOptionId": "b",
      "correctOptionIds": null,
      "allowMultipleAnswers": false
    },
    {
      "type": "multipleChoice",
      "id": "q-primes",
      "prompt": "Which of these numbers are prime numbers?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Maths",
      "adminNotes": "Multiple answers",
      "media": [],
      "solutionMedia": [],
      "hints": [
        {"text": "A prime is divisible only by 1 and itself.", "media": [], "cost": 2}
      ],
      "scoringRule": {"type": "fixed", "correctPoints": 20, "wrongPoints": -5},
      "options": [
        {"id": "a", "label": "2"},
        {"id": "b", "label": "9"},
        {"id": "c", "label": "13"},
        {"id": "d", "label": "21"}
      ],
      "correctOptionId": null,
      "correctOptionIds": ["a", "c"],
      "allowMultipleAnswers": true
    },
    {
      "type": "buzzer",
      "id": "q-gold",
      "prompt": "Which chemical element has the symbol “Au”?",
      "timeLimitMs": 20000,
      "softTimeLimit": false,
      "category": "Chemistry",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "firstBuzzer", "points": 15, "penalty": -5, "rankDecay": 5},
      "expectedAnswer": "Gold",
      "lockOutOnMiss": true,
      "hostEndsRound": false,
      "retryLimit": null
    },
    {
      "type": "shortAnswer",
      "id": "q-planet",
      "prompt": "What is the name of the largest planet in our solar system?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Astronomy",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "acceptedAnswers": ["Jupiter"],
      "maxEdits": 1,
      "manualGrading": false
    },
    {
      "type": "ordering",
      "id": "q-order",
      "prompt": "Sort the inventions from oldest to newest.",
      "timeLimitMs": 40000,
      "softTimeLimit": false,
      "category": "History",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 15, "wrongPoints": 0},
      "items": [
        {"id": "telephone", "label": "Telephone"},
        {"id": "printing", "label": "Printing press"},
        {"id": "internet", "label": "Internet"}
      ],
      "correctOrder": ["printing", "telephone", "internet"]
    },
    {
      "type": "matching",
      "id": "q-matching",
      "prompt": "Match the composers with their works.",
      "timeLimitMs": 45000,
      "softTimeLimit": false,
      "category": "Music",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 15, "wrongPoints": 0},
      "leftItems": [
        {"id": "mozart", "label": "Mozart"},
        {"id": "beethoven", "label": "Beethoven"}
      ],
      "rightItems": [
        {"id": "flute", "label": "The Magic Flute"},
        {"id": "ninth", "label": "Symphony No. 9"}
      ],
      "correctPairs": {"mozart": "flute", "beethoven": "ninth"}
    },
    {
      "type": "estimation",
      "id": "q-estimate",
      "prompt": "How tall is the Eiffel Tower (including antennas)?",
      "timeLimitMs": 30000,
      "softTimeLimit": false,
      "category": "Buildings",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 20, "wrongPoints": 0},
      "correctValue": 330, "minAccepted": 320, "maxAccepted": 340,
      "zeroScale": 1,
      "unit": "m"
    },
    {
      "type": "trueFalse",
      "id": "q-truefalse",
      "prompt": "This code prints 4.",
      "timeLimitMs": 20000,
      "softTimeLimit": false,
      "category": "Technology",
      "adminNotes": "",
      "media": [
        {"type": "code", "caption": "", "hideDetails": false, "code": "print(2 + 2);", "language": "dart"}
      ],
      "solutionMedia": [
        {"type": "image", "caption": "Picture for the solution", "hideDetails": false, "zoom": true, "asset": {"id": "6eac1db9594fa41f49be880b8dd3fa9d0a2c81361a6b2ee54896688adfb9fbbf", "mimeType": "image/svg+xml", "data": "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMjAgODAiPjxyZWN0IHdpZHRoPSIxMjAiIGhlaWdodD0iODAiIGZpbGw9IiMxZTg4ZTUiLz48Y2lyY2xlIGN4PSI2MCIgY3k9IjQwIiByPSIyNCIgZmlsbD0iI2ZmZWIzYiIvPjwvc3ZnPg=="}}
      ],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": true
    },
    {
      "type": "location",
      "id": "q-karte",
      "prompt": "Where is the Eiffel Tower?",
      "timeLimitMs": 45000,
      "softTimeLimit": false,
      "category": "Buildings",
      "adminNotes": "",
      "media": [],
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 20, "wrongPoints": 0},
      "target": {"latitude": 48.8584, "longitude": 2.2945},
      "targetLabel": "Eiffel Tower, Paris",
      "fullPointsKm": 5,
      "zeroPointsKm": 800,
      "startCenter": {"latitude": 20, "longitude": 0},
      "startZoom": 1.5
    }
  ],
  "teams": [],
  "format": {"type": "standard", "revealMode": "afterEachQuestion"},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Jeopardy (two teams, Daily Double)

```json quizmo-example
{
  "schemaVersion": 18,
  "id": "quiz-ai-jeopardy-example",
  "name": "Jeopardy: Nature & Technology",
  "description": "Small board with two categories.",
  "category": "Jeopardy",
  "questions": [
    {
      "type": "shortAnswer", "id": "n1", "prompt": "How many legs does a spider have?",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": "Nature", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "acceptedAnswers": ["8", "eight"], "maxEdits": 0, "manualGrading": false
    },
    {
      "type": "trueFalse", "id": "n2", "prompt": "Whales are fish.",
      "timeLimitMs": 15000, "softTimeLimit": false, "category": "Nature", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": false
    },
    {
      "type": "buzzer", "id": "t1", "prompt": "Who is considered the inventor of the World Wide Web?",
      "timeLimitMs": 0, "softTimeLimit": false, "category": "Technology", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "firstBuzzer", "points": 10, "penalty": 0, "rankDecay": 0},
      "expectedAnswer": "Tim Berners-Lee", "lockOutOnMiss": true, "hostEndsRound": false, "retryLimit": null
    },
    {
      "type": "multipleChoice", "id": "t2", "prompt": "What does “CPU” stand for?",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": "Technology", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Central Processing Unit"},
        {"id": "b", "label": "Computer Power Unit"}
      ],
      "correctOptionId": "a", "correctOptionIds": null, "allowMultipleAnswers": false
    }
  ],
  "teams": [
    {"id": "team-red", "name": "Red", "color": "red"},
    {"id": "team-blue", "name": "Blue", "color": "blue"}
  ],
  "format": {
    "type": "jeopardy",
    "board": {
      "categories": [
        {"name": "Nature", "cells": [
          {"questionId": "n1", "dailyDouble": false},
          {"questionId": "n2", "dailyDouble": true}
        ]},
        {"name": "Technology", "cells": [
          {"questionId": "t1", "dailyDouble": false},
          {"questionId": "t2", "dailyDouble": false}
        ]}
      ],
      "rowPoints": [100, 200],
      "penalizeWrongAnswers": false,
      "allowSteal": true
    }
  },
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Pokerchips (teams are created when joining)

```json quizmo-example
{
  "schemaVersion": 18,
  "id": "quiz-ai-poker-example",
  "name": "Pokerchips: How sure are you?",
  "description": "Teams bet chips on their knowledge.",
  "category": "Poker",
  "questions": [
    {
      "type": "estimation", "id": "p1", "prompt": "In which year did the Berlin Wall fall?",
      "timeLimitMs": 30000, "softTimeLimit": false, "category": "History", "adminNotes": "Poker only pays out for an exactly correct answer.",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctValue": 1989, "zeroScale": 1, "unit": ""
    },
    {
      "type": "multipleChoice", "id": "p2", "prompt": "What is the largest organ of the human body?",
      "timeLimitMs": 25000, "softTimeLimit": false, "category": "Biology", "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Liver"},
        {"id": "b", "label": "Skin"},
        {"id": "c", "label": "Lungs"}
      ],
      "correctOptionId": "b", "correctOptionIds": null, "allowMultipleAnswers": false
    }
  ],
  "teams": [],
  "format": {"type": "poker", "startingChips": 100, "minStake": 5, "maxStake": 50},
  "jokers": [
    {"type": "credit", "usesPerTeam": 1, "maxLoss": 1},
    {"type": "forcedStake", "usesPerTeam": 1, "stake": 30, "cost": 10, "lossFactor": 2}
  ],
  "slides": [
    {"id": "folie-start", "title": "Willkommen!", "text": "Gleich geht es los.", "media": [], "beforeQuestionId": "p1"},
    {"id": "folie-ende", "title": "Das Ergebnis ist unterwegs!", "text": "", "media": []}
  ],
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```

### Biggest Snowflake (the rarest answer wins)

```json quizmo-example
{
  "schemaVersion": 18,
  "id": "quiz-ai-snowflake-example",
  "name": "Biggest Snowflake: who thinks differently?",
  "description": "No correct solution: whoever answers differently from the majority scores.",
  "category": "Party",
  "questions": [
    {
      "type": "trueFalse", "id": "s1", "prompt": "Pineapple belongs on pizza.",
      "timeLimitMs": 20000, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": null
    },
    {
      "type": "multipleChoice", "id": "s2", "prompt": "Which season is the best?",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "options": [
        {"id": "a", "label": "Spring"},
        {"id": "b", "label": "Summer"},
        {"id": "c", "label": "Autumn"},
        {"id": "d", "label": "Winter"}
      ],
      "correctOptionId": null, "correctOptionIds": null, "allowMultipleAnswers": false
    },
    {
      "type": "ordering", "id": "s3", "prompt": "Sort from most important to least important.",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "items": [
        {"id": "a", "label": "Sleep"},
        {"id": "b", "label": "Food"},
        {"id": "c", "label": "Wi-Fi"}
      ],
      "correctOrder": null
    },
    {
      "type": "matching", "id": "s4", "prompt": "Which drink goes with which time of day?",
      "timeLimitMs": 0, "softTimeLimit": false, "category": null, "adminNotes": "",
      "media": [], "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "leftItems": [
        {"id": "l1", "label": "Morning"},
        {"id": "l2", "label": "Evening"}
      ],
      "rightItems": [
        {"id": "r1", "label": "Coffee"},
        {"id": "r2", "label": "Tea"}
      ],
      "correctPairs": null
    }
  ],
  "teams": [],
  "format": {"type": "snowflake", "scoring": "graded"},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```
