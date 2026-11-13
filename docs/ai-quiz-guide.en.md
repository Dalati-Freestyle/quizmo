# Creating a Quizmo quiz with an AI assistant

<!--
  This file is both the guide in the repository and the file Quizmo ships
  under Settings → "Create a quiz with AI" (asset). The German version is
  ai-quiz-guide.md; always keep both in sync.
  test/core/data/ai_quiz_guide_test.dart imports every example below and fails
  as soon as the schemaVersion changes. Then update this guide to the new
  schema.
-->

Quizmo schema version of this guide: **9**

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

* Ask only the most necessary questions (usually just: topic; language or
  audience if not obvious).
* Decide everything else yourself: format, teams or solo, time limits,
  scoring, number and kind of questions (mixed, at least three different
  question types).
* Then output the finished file right away.

### Guided mode

First settle **everything that applies to the whole quiz**, before the first
question is written. Ask actively and suggest sensible defaults:

1. **Quiz format** – Standard, Jeopardy or Pokerchips (see section 3) with its
   format rules (board layout, minus points, steal, starting chips, solutions
   after every question or at the end).
2. **Teams or solo** – predefined teams (names, colours) or single players.
3. **Time limits** – no time limit (the host ends the round) or a default time
   per question, hard or soft limit.
4. **Scoring** – fixed points, speed bonus, buzzer scoring, minus points for
   wrong answers.
5. **Content** – topic, audience, difficulty, language, number of questions
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
   file. You cannot embed the person's own images, audio files and videos:
   after the import they upload them in the quiz editor via "Media" on the
   question (or solution).

## 2. File structure

```text
{
  "schemaVersion": 9,               // always exactly 9
  "id": "quiz-…",                   // unique ID, only a-z, 0-9 and -
  "name": "Title",
  "description": "Short description (not empty)",
  "category": "Category (not empty)",
  "questions": [ … ],               // see section 4
  "teams": [ … ],                   // empty = solo (poker: teams are created when joining)
  "format": { … },                  // see section 3
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
| Pokerchips | `{"type": "poker", "startingChips": 100}` | Teams bet chips before every question (1–1,000,000 starting chips). Correct = twice the stake back, wrong = stake lost. `teams` may be empty. |

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
* Every question type works in every format.

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

## 5. Question types

| `type` | Additional fields | Rules |
| --- | --- | --- |
| `multipleChoice` | `options` (list of `{"id","label"}`), `correctOptionId`, `correctOptionIds`, `allowMultipleAnswers` | At least 2 options. Single choice: `correctOptionId` = ID, `correctOptionIds` = `null`, `allowMultipleAnswers` = `false`. Multiple choice: `correctOptionId` = `null`, `correctOptionIds` = list, `allowMultipleAnswers` = `true`. |
| `buzzer` | `expectedAnswer`, `lockOutOnMiss`, `hostEndsRound`, `retryLimit` | Whoever buzzes first answers out loud; the host judges. `retryLimit`: `null` = unlimited, otherwise ≥ 0. Scoring usually `firstBuzzer`. |
| `shortAnswer` | `acceptedAnswers` (list), `maxEdits` (0–5), `manualGrading` | Free text. At least one accepted answer. `maxEdits` = allowed typos. `manualGrading: true` = the host grades by hand. |
| `ordering` | `items` (list of `{"id","label"}`), `correctOrder` (list of the IDs) | Order. At least 2 items; `correctOrder` contains every ID exactly once. |
| `matching` | `leftItems`, `rightItems` (each a list of `{"id","label"}`), `correctPairs` (`{"leftId": "rightId"}`) | Matching. Pair every left ID with exactly one unique right partner. |
| `estimation` | `correctValue` (number), `zeroScale` (> 0), `unit` | Estimate. Points in proportion `max(0, 1 − |answer − target| / |target|)`; for target 0, `zeroScale` replaces the denominator. |
| `trueFalse` | `correctAnswer` (`true`/`false`) | True/false. |

## 6. Media

Embedded files (images, audio, MP4) contain Base64 data with a SHA-256 ID.
**Do not create such uploads** – a chat model cannot do that reliably. Leave
`media`/`solutionMedia` empty or use only these references without file
content. Tell the person that they have to add their own images, audio and
videos after the import in the quiz editor via "Media" on the question or
solution; feel free to suggest which media would fit where:

| Kind | JSON |
| --- | --- |
| YouTube video | `{"type": "video", "caption": "", "hideDetails": false, "asset": null, "youtubeId": "aqz-KE-bpKQ"}` – only the video ID; only use real, existing videos. Needs internet. |
| Map section | `{"type": "geo", "caption": "Berlin", "hideDetails": false, "latitude": 52.52, "longitude": 13.405, "zoom": 10.0}` – OpenStreetMap, needs internet. |
| Code/text | `{"type": "code", "caption": "", "hideDetails": false, "code": "print(1 + 1);", "language": "dart"}` – syntax highlighting; `language` e.g. `dart`, `python`, `javascript`, `text`. |

`hideDetails: true` hides caption/title on player and TV devices. At most 10
attachments per question (question and solution together).

## 7. Checklist before the output

- [ ] `"schemaVersion": 9` is at the very top.
- [ ] `name`, `description` and `category` are not empty.
- [ ] All IDs are unique and not empty.
- [ ] Every question has a text, a time limit ≥ 0 (0 = none; a speed bonus
      needs > 0) and a valid `scoringRule`.
- [ ] Every question has a complete, valid solution (see section 5).
- [ ] Jeopardy: every `questionId` exists, no question twice, row points > 0,
      every category has a name, at least two teams.
- [ ] Poker: `startingChips` between 1 and 1,000,000.
- [ ] Teams have `id`, `name` and `color` (a palette name from section 2).
- [ ] No uploaded media (`asset` with data); only YouTube, map, code. The
      person adds their own images, audio and videos afterwards in the quiz
      editor.
- [ ] Valid JSON: double quotes, no comments, no trailing commas.

## 8. Complete examples

The following files are valid and import unchanged.

### Standard (solo, every question type)

```json quizmo-example
{
  "schemaVersion": 9,
  "id": "quiz-ai-standard-example",
  "name": "General knowledge in brief",
  "description": "Eight questions with every question type.",
  "category": "General knowledge",
  "questions": [
    {
      "type": "multipleChoice",
      "id": "q-capital",
      "prompt": "Which city is the capital of Canada?",
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
      "correctValue": 330,
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
      "solutionMedia": [],
      "scoringRule": {"type": "fixed", "correctPoints": 10, "wrongPoints": 0},
      "correctAnswer": true
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
  "schemaVersion": 9,
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
  "schemaVersion": 9,
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
  "format": {"type": "poker", "startingChips": 100},
  "createdAtMicros": 1767225600000000,
  "updatedAtMicros": 1767225600000000
}
```
