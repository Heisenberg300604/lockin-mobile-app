# LockIn (Flutter)

LockIn helps people **build** good habits or **quit** bad ones by locking in a
commitment: a target, a duration, a pace, and a reward. Each day you check in;
if you miss a day the attempt breaks, you reflect privately, and you can
restart.

This is the Flutter rewrite of the React Native / Expo app in `../Lock-In`.
The screens, colours, fonts, icons, spacing and business rules are the same.
What changed is the technology underneath, and the goal is a codebase that is
**easy to read, easy to extend, and ready for the App Store / Play Store**.

> **Current scope.** The UI and all business rules work end-to-end, with data
> kept **on the device**. Authentication uses **Clerk**. Your NestJS backend is
> *not* connected yet; `docs/BACKEND_INTEGRATION.md` explains exactly where
> and how to plug it in.

## Run it

```sh
flutter pub get
flutter run --dart-define-from-file=env/dev.json     # with Clerk
flutter run                                           # without keys: "Continue on this device" only
flutter test                                          # 34 business-rule tests
```

Copy `env/dev.example.json` to `env/dev.json` and fill in your Clerk
publishable key. Full instructions: [docs/SETUP.md](docs/SETUP.md).

## Where things live

```text
lib/
  main.dart            entry point (calls bootstrap)
  bootstrap.dart       async start-up work before the first frame
  app/                 app root, router (all screens/routes), bottom-tab shell
  core/                shared code with no business knowledge
    config/            build-time keys/switches (--dart-define)
    theme/             colours, text styles, ThemeData  (the design tokens)
    widgets/           the design system: buttons, fields, cards, modal, ...
    motion/            animation helpers + "reduce motion"
    utils/             calendar-date maths, haptics
  features/            one folder per product feature
    auth/              Clerk sign-in/up/reset, session
    commitments/       the heart of the app
      domain/          plain Dart rules: models, schedule, lifecycle, validation
      data/            repository interface + on-device implementation
      application/     Riverpod controller (state + actions for screens)
      presentation/    screens and widgets
    reminders/         daily reminder planning + OS notifications
    settings/          preferences + Settings screen
test/                  unit tests for the rules
docs/                  guides (read these!)
```

## Read next

| Document | What you will learn |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the app is organised, how state flows, why Riverpod, how to add a feature |
| [docs/MIGRATION_MAP.md](docs/MIGRATION_MAP.md) | Every React Native file and what replaced it; React ➜ Flutter concept cheat-sheet |
| [docs/SETUP.md](docs/SETUP.md) | Keys, Clerk dashboard settings, running, store builds |
| [docs/BACKEND_INTEGRATION.md](docs/BACKEND_INTEGRATION.md) | Connecting your NestJS API |
