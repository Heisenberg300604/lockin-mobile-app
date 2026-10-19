# LockIn

**Build better habits. Break unwanted ones. Keep your commitment.**

LockIn is a Flutter mobile app for turning a goal into a concrete commitment. Choose what you want to build or quit, define a target and duration, follow a schedule, and check in as you go. If an attempt breaks, you can review what happened and start a new attempt.

The app uses a warm, minimal interface with bold typography, tactile offset shadows, and a restrained mint accent. Its codebase is organized by feature and layer so product rules can be tested independently of the UI and data source.

> **Project status:** The Flutter client includes an authenticated LockIn REST API integration. It uses Clerk for authentication and the configured API for commitment data. The available API has some constraints compared with the legacy UI; see [Backend integration](docs/BACKEND_INTEGRATION.md) before changing check-in or restart behaviour.

## Contents

- [Features](#features)
- [Technology](#technology)
- [Project structure](#project-structure)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Run, test, and analyse](#run-test-and-analyse)
- [Architecture and data flow](#architecture-and-data-flow)
- [Design system](#design-system)
- [Backend notes and current limitations](#backend-notes-and-current-limitations)
- [Documentation](#documentation)
- [Security notes](#security-notes)
- [Contributing](#contributing)

## Features

- **Build or quit:** Create a commitment around a positive habit or an unwanted behaviour.
- **Defined targets:** Set a duration, target, pace, and reward for a commitment.
- **Daily check-ins:** Record progress and see commitment status evolve over time.
- **Focus, History, and Settings:** Navigate the main tracking experience, past attempts, and preferences.
- **Commitment lifecycle:** Pause and resume eligible commitments, handle broken attempts, reflect, and restart.
- **Reminders:** Plan and synchronize local notifications with the user's reminder preferences.
- **Authentication:** Clerk-based sign-in and session handling, with secure session persistence through the platform's secure storage.
- **Thoughtful interaction design:** Shared buttons, cards, fields, modals, haptic feedback, motion helpers, and reduced-motion support.
- **Testable business rules:** Habit scheduling, validation, lifecycle transitions, and reminder planning are separated from Flutter widgets.

## Technology

| Area | Technology |
| --- | --- |
| App framework | Flutter |
| Language | Dart |
| State management | Riverpod 3 (`flutter_riverpod`) |
| Navigation | `go_router` |
| Authentication | Clerk Flutter SDK |
| REST networking | Dio |
| Local preferences and supporting storage | `shared_preferences` |
| Secure auth-session storage | `flutter_secure_storage` |
| Local notifications and time zones | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| SVG rendering | `flutter_svg` |
| Tests and linting | `flutter_test`, `flutter_lints` |

Dependency versions and SDK constraints are maintained in [`pubspec.yaml`](pubspec.yaml).

## Project structure

```text
lib/
├── main.dart                   # Entry point
├── bootstrap.dart              # Prepare services before the first frame
├── app/
│   ├── app.dart                # App root and theme
│   ├── router.dart              # Routes and auth redirects
│   └── tab_shell.dart           # Focus / History / Settings navigation
├── core/
│   ├── config/                  # Build-time configuration
│   ├── network/                 # Authenticated API client
│   ├── theme/                   # Centralized colours, typography, ThemeData
│   ├── widgets/                 # Reusable design-system components
│   ├── motion/                  # Animation and reduced-motion helpers
│   └── utils/                   # Calendar dates, haptics, shared utilities
└── features/
    ├── auth/                    # Auth gateway and session state
    ├── commitments/
    │   ├── domain/               # Models, schedules, validation, lifecycle rules
    │   ├── data/                 # Repository contract and API/local implementations
    │   ├── application/          # Riverpod controllers and providers
    │   └── presentation/         # Screens and commitment widgets
    ├── reminders/                # Reminder planning, scheduling, notifications
    └── settings/                 # Preferences and settings UI

test/                             # Automated tests
assets/fonts/                     # Bundled Inter and Feather fonts
docs/                             # Setup, architecture, migration, API notes
```

The exact file list may evolve; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the current architectural guide.

## Requirements

- Flutter **3.44 or newer** (with a compatible Dart SDK; see `pubspec.yaml`).
- Android Studio / Android SDK for Android builds, or Xcode for iOS builds.
- A Clerk application and its **publishable key** for authenticated sign-in.
- Access to the LockIn REST API environment you intend to use.

Run `flutter doctor` and resolve any platform setup issues before building.

## Getting started

### 1. Get the code and dependencies

```bash
git clone https://github.com/Heisenberg300604/lockin-mobile-app.git
cd lockin-mobile-app
flutter pub get
```

### 2. Configure your development environment

Copy the example configuration and add your Clerk publishable key:

```bash
cp env/dev.example.json env/dev.json
```

Edit `env/dev.json` as described below. The local `env/dev.json` file is ignored by Git; do not force-add it.

### 3. Run the app

```bash
flutter run --dart-define-from-file=env/dev.json
```

For platform-specific build setup, Clerk dashboard requirements, and release steps, read [`docs/SETUP.md`](docs/SETUP.md).

## Configuration

The app reads configuration at build/run time using Dart defines. The example file should use this shape:

```json
{
  "CLERK_PUBLISHABLE_KEY": "pk_test_...",
  "API_URL": "https://lockin-a0os.onrender.com/api/v1",
  "ENABLE_DEVICE_MODE": false
}
```

| Key | Purpose |
| --- | --- |
| `CLERK_PUBLISHABLE_KEY` | Clerk publishable key used by the Flutter auth SDK. |
| `API_URL` | LockIn API base URL, without a trailing slash. If omitted, the app uses the default API URL defined in `AppConfig`. |
| `ENABLE_DEVICE_MODE` | Controls whether the local-device continuation option is offered on the sign-in screen. It defaults to `false`. |

`API_BASE_URL` is supported as a temporary legacy fallback; prefer `API_URL` for new configuration. Do not put Clerk secret keys, database credentials, or other private secrets in a mobile app or its Dart defines. Values embedded in a client build can be extracted.

## Run, test, and analyse

```bash
# Run on a connected device or emulator
flutter run --dart-define-from-file=env/dev.json

# Run automated tests
flutter test

# Run static analysis and lints
flutter analyze

# List available Flutter devices
flutter devices
```

The tests cover domain rules such as schedule calculations, validation, commitment lifecycle transitions, and reminder planning. This README does not claim a test run has passed; run the commands above against your local toolchain before submitting changes.

## Architecture and data flow

LockIn uses a layered, feature-first architecture. Dependencies flow inward/downward, keeping business rules independent from widgets and persistence details.

```text
Presentation (screens and widgets)
          │ watches state / invokes actions
          ▼
Application (Riverpod controllers and providers)
          │ calls repository contracts
          ▼
Data (API or local repository implementation)
          │ maps and persists data
          ▼
Domain (plain Dart models and business rules)
```

- **Domain:** Models, schedule calculations, validation, and lifecycle transitions. This layer should not depend on Flutter, storage, or networking.
- **Data:** Repository implementations and API access. Screens should not make HTTP calls directly.
- **Application:** Riverpod controllers expose state and actions to the UI.
- **Presentation:** Screens and widgets render state and dispatch user actions; business rules belong elsewhere.

For the detailed rationale, provider graph, lifecycle examples, and instructions for adding features, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Design system

The interface uses a centralized palette and reusable widgets rather than screen-by-screen styling.

| Token | Value | Role |
| --- | --- | --- |
| Primary ink | `#251F1A` | Main text and primary controls |
| Focus ink | `#0D0805` | High-emphasis text |
| Focus canvas | `#F4F1EA` | Main app background |
| Setup canvas | `#F4EFE6` | Authentication and setup backgrounds |
| Card surface | `#E6E1DA` | Cards and tracking surfaces |
| Mint accent | `#6CF8BB` | Selected navigation accent |
| Success | `#00714D` | Progress and successful check-ins |

Use the constants in [`lib/core/theme/app_colors.dart`](lib/core/theme/app_colors.dart) instead of hard-coding colours. The custom `RaisedBox` widget implements the interface's solid offset-shadow treatment. Shared typography, controls, and animation helpers live in `lib/core/widgets/` and `lib/core/motion/`.

## Backend notes and current limitations

The Flutter client includes `RemoteCommitmentRepository` and an authenticated `ApiClient`; the REST API is the commitment data source when using the configured backend. The client obtains a fresh Clerk token for requests and handles transient network failures with a retry.

The mobile client also reflects current API limitations. In particular, the documented API supports a check-in for the commitment's current time-zone date, and restart is implemented as a new server commitment because the API does not expose a persisted attempt-link/restart endpoint. Some legacy catch-up/count-based interactions therefore cannot be represented as if the server saved them. Review [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md) before modifying these flows.

## Documentation

| Document | Description |
| --- | --- |
| [`docs/SETUP.md`](docs/SETUP.md) | Environment setup, Clerk configuration, running, and release checklist |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layers, state management, data flow, domain rules, and feature workflow |
| [`docs/BACKEND_INTEGRATION.md`](docs/BACKEND_INTEGRATION.md) | API configuration, authentication, endpoint mapping, and API constraints |
| [`docs/MIGRATION_MAP.md`](docs/MIGRATION_MAP.md) | React Native-to-Flutter file and concept mapping |

## Security notes

- Only use a Clerk **publishable** key in the mobile client.
- Never commit `env/dev.json`, secret keys, tokens, or private credentials.
- Authentication tokens are fetched for requests by the API client; do not add token persistence or logging without reviewing the security implications.
- Treat API validation and server limitations as authoritative; do not display an action as saved when the backend rejected it.

## Contributing

1. Create a focused branch for your change.
2. Keep domain rules in the domain layer and add or update tests for behaviour changes.
3. Reuse the existing theme tokens and shared widgets rather than introducing one-off styles.
4. Run `dart format .`, `flutter analyze`, and `flutter test` before opening a pull request.
5. Describe the change, validation performed, and any known limitations in the pull request.

For feature-specific guidance, start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
