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
│   └── handlers/        # API, CORS and WebSocket message handlers
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

### Adding Scoring Rules / Team Modes
* Implement rules inside `lib/core/engine/scoring_rules.dart`.
* Always write unit tests under `test/core/engine/` for any new scoring rule or team aggregation logic before connecting it to UI components.

---

## 5. Performance & UX Rules
* **Buzzer Responsiveness:** Always bind buzzer buttons to `Listener.onPointerDown` instead of `GestureDetector.onTap` to bypass gesture delay.
* **Bundle Size:** Keep web player assets lightweight. Defer-load host or admin tools so web players joining via QR/Discord load instantly.