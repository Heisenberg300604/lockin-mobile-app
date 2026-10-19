# Architecture

This document explains **how the app is built and why**, so you can read any
file and know where it fits. If you only read one doc, read this one.

## 1. The big idea: layers that only talk downwards

```text
┌─────────────────────────────────────────────────────────────┐
│ presentation   screens and widgets (what the user sees)     │
│                 ↓ reads state, calls actions               │
├─────────────────────────────────────────────────────────────┤
│ application    Riverpod controllers (state + actions)       │
│                 ↓ asks for data / changes                   │
├─────────────────────────────────────────────────────────────┤
│ data           repositories (where data lives)              │
│                 ↓ uses                                       │
├─────────────────────────────────────────────────────────────┤
│ domain         pure Dart rules (no Flutter, no storage)     │
└─────────────────────────────────────────────────────────────┘
```

* **domain** (`features/commitments/domain/`) is the *business*. "When does a
  streak break?", "What counts as a successful week?". It is plain Dart: no
  widgets, no storage, no network, no clock reads. Because of that it is fast to
  test (see `test/`) and never needs to change when the UI or backend changes.
* **data** (`.../data/`) decides *where* information is stored. The app talks
  to the abstract `CommitmentRepository`. Today the implementation is
  `LocalCommitmentRepository` (JSON on the device). Tomorrow it can be a class
  that calls your NestJS API.
* **application** (`.../application/`) is the *state* the screens watch plus the
  *actions* they trigger (`create`, `log`, `pause`, ...). It is built with Riverpod.
* **presentation** (`.../presentation/`) is the UI. Screens contain layout and
  small bits of local UI state (which tab, which text is typed). They never
  contain business rules.

A layer may only use the layers *below* it. That rule is what stops the code
from turning into a tangle as it grows.

## 2. Feature-first folders

Code is grouped by **feature** (`auth`, `commitments`, `reminders`, `settings`),
and inside each feature by layer. When you work on "reminders" everything you
need is in one folder. Code that is shared by all features lives in `core/`
(design system, theme, helpers) and must never import from `features/`
(with the single exception of tiny model types, kept to a minimum).

## 3. State management with Riverpod

"State management" answers: *where does shared data live, and how do widgets
find out it changed?* We use **Riverpod 3** (`flutter_riverpod`), the community
standard recommended for new apps.

Vocabulary:

| Term | Meaning | Example in this app |
| --- | --- | --- |
| **Provider** | A named, lazily created, cached value anyone can read | `clockProvider`, `keyValueStoreProvider` |
| **Notifier** | A provider that owns *state* and has methods that change it | `CommitmentsController`, `PreferencesController`, `SessionController` |
| **`ref.watch(p)`** | "Give me `p`, and rebuild me whenever it changes" | used in `build()` of widgets |
| **`ref.read(p)`** | "Give me `p` once, don't rebuild" | used inside tap handlers |
| **`ConsumerWidget`** | A widget that has a `ref` | most screens |

Rules of thumb used throughout:

1. **Widgets watch, controllers change.** A widget calls
   `ref.read(commitmentsProvider.notifier).log(...)`; it never edits data itself.
2. **State is immutable.** A controller replaces `state` with a new object
   (`state = state.copyWith(...)`). Riverpod notices the replacement and
   rebuilds only the widgets that watched it.
3. **Use `select` to rebuild less.** `ref.watch(p.select((s) => s.now))`
   rebuilds only when `now` changes, not when anything else in `s` does.
4. **Providers depend on providers.** `commitmentRepositoryProvider` watches
   `sessionProvider`. When the user signs out and another signs in, the
   repository, and therefore the controller and all screens' data, are rebuilt
   automatically for the new account. No manual reset code.

### The providers, at a glance

```text
sharedPreferencesProvider ─┬─► keyValueStoreProvider ─┬─► commitmentRepositoryProvider ─► commitmentsProvider
(set in bootstrap)         │                          │            ▲ watches
                           │                          └─► preferencesProvider ─► hapticsProvider, reducedMotionProvider
authGatewayProvider ─► sessionProvider ───────────────┘
clockProvider (overridable in tests)
notificationServiceProvider ─► reminderSchedulerProvider, reminderSyncProvider (effect)
```

## 4. How one tap flows through the app

*User taps "Done!" in the log dialog.*

1. `LogModal` (presentation) calls `commitmentsProvider.notifier.log(c, date, 1)`.
2. `CommitmentsController.log` (application) calls `repository.log(...)`.
3. `LocalCommitmentRepository.log` (data):
   queues the operation → reads the stored JSON → applies
   time-based rules (`reconcile`) → validates (`validateCheckIn`, domain) →
   writes the new JSON.
4. The controller plays a success haptic and calls `refresh()`, which reloads
   the snapshot and sets a new `state`.
5. Riverpod rebuilds every widget that watches that state: the tracking row's
   progress bar animates to full, the calendar cell turns green.

## 5. The business rules (domain)

| File | Responsibility |
| --- | --- |
| `models.dart` | Immutable data types and their JSON |
| `schedule.dart` | Which days are due, progress, streaks, the 24h catch-up window |
| `validation.dart` | Rules for new commitments and check-ins |
| `lifecycle.dart` | Pause/resume/fail/restart and the time-based `reconcile` |
| `reminders/domain/reminder_plan.dart` | Which reminders should exist |

Key ideas (full details in the original `docs/behavior-spec.md`):

* **Calendar days are strings** (`"2026-06-04"`), never `DateTime`s, so a habit
  can't slip a day because of time zones. Instants are only computed when
  needed (deadlines) from a day + the attempt's IANA time zone.
* **Nothing runs on a timer to "break" a habit.** Whenever data is read or
  written, `reconcile()` looks at the clock and updates anything that has
  expired or completed. It is idempotent, so running it twice is harmless.
* **Saves are absolute and idempotent.** A check-in stores "3 of 10", not
  "+1"; creating/restarting takes a request id. Retrying never double-counts.
* **Restart creates a new linked attempt.** History is never rewritten.

## 6. The design system (`core/widgets`)

The original app had one 1,100-line `ui.tsx`. Here it is split into focused
files you can open independently:

| Widget | File |
| --- | --- |
| `RaisedBox` – the signature hard drop-shadow | `raised_box.dart` |
| `LockButton`, `IconBtn` | `lock_button.dart` |
| `ChoiceCard` | `choice_card.dart` |
| `AppField` | `app_field.dart` |
| `Panel`, `AppCard`, `AppDivider` | `containers.dart` |
| `ErrorNote`, `Notice`, `AppProgressBar`, `StepProgress` | `status_widgets.dart` |
| `AppScreen`, `AppHeader`, `Brand` | `app_screen.dart` |
| `showAppModal`, `ModalCard` | `modal_card.dart` |
| `Counter` | `counter.dart` |
| `Label`, `ScreenTitle`, `SectionLabel` | `typography.dart` |

Colours and text styles are defined once in `core/theme/`. **Never write a hex
colour in a screen**; add it to `AppColors` so the design stays consistent.

## 7. Animation and accessibility

* Flutter animates by *tweening to a target* (implicit animations:
  `AnimatedContainer`, `TweenAnimationBuilder`, `AnimatedSwitcher`). That
  replaced Reanimated's shared values. Durations come from `Motion` in
  `core/motion/motion_widgets.dart` (the project's motion spec).
* `reducedMotionProvider` combines the phone's accessibility setting and the
  in-app switch. Widgets that animate check it and skip movement.
* Tap targets are at least 48px tall, icon buttons and fields carry
  screen-reader labels, status is never colour-only, and system font scaling
  is respected (text wraps instead of clipping).

## 8. Authentication

`features/auth/data/auth_gateway.dart` defines what the app needs from an auth
provider. `ClerkAuthGateway` implements it with Clerk's Flutter SDK, keeping
session tokens in the Keychain/Keystore (`SecureClerkPersistor`). Screens only
know the gateway interface, so Clerk's beta SDK is isolated in one file.
`SessionController` turns "Clerk user or device mode" into an `Identity`, and
the router redirects based on it.

## 9. Testing

* `test/domain/*` run the ported business-rule suites (34 tests): schedule
  maths, DST/time-zone boundaries, pause/resume, expiry, restart idempotency,
  reminder planning. Run `flutter test`.
* To test a screen, override providers: `ProviderScope(overrides: [clockProvider.overrideWithValue(() => fixedTime), ...])`.

## 10. How to add a feature (checklist)

1. Create `lib/features/<name>/{domain,data,application,presentation}`.
2. Put rules in `domain` first and write a test for them.
3. Define a repository interface in `data`, with a local or fake implementation.
4. Expose it through a `Notifier` in `application`.
5. Build screens in `presentation` with the shared widgets.
6. Add the route in `app/router.dart`.
