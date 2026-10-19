# Migration map: React Native ➜ Flutter

Use this when you know where something was in the old app and want to find it
here (or the reverse).

## File by file

| React Native (`Lock-In/`) | Flutter (`lockin_flutter/lib/`) |
| --- | --- |
| `design-tokens.json`, `src/theme.ts` | `core/theme/app_colors.dart`, `app_text.dart`, `app_theme.dart` |
| `src/components/ui.tsx` (1,100 lines) | split into `core/widgets/*` (see ARCHITECTURE §6) |
| `src/components/motion.tsx` | `core/motion/motion_widgets.dart` |
| `src/components/commitments.tsx` | `features/commitments/presentation/widgets/{commitment_card,tracking_row,log_modal}.dart` |
| `src/domain/commitments.ts` | `features/commitments/domain/{models,schedule,validation}.dart` + `core/utils/calendar_date.dart` |
| `src/domain/lifecycle.ts` | `features/commitments/domain/lifecycle.dart` |
| `src/domain/reminders.ts` | `features/reminders/domain/reminder_plan.dart` |
| `src/data/local-repository.ts` | `features/commitments/data/local_commitment_repository.dart` |
| `src/data/repository.ts` (Supabase cloud repo) | **not ported** (backend comes later); see `docs/BACKEND_INTEGRATION.md` |
| `src/data/reminder-scheduler.ts` | `features/reminders/data/reminder_scheduler.dart` |
| `src/lib/notifications*.ts` | `features/reminders/data/notification_service.dart` |
| `src/lib/feedback.ts` | `core/utils/haptics.dart` |
| `src/lib/supabase.ts` | **not ported** (Supabase is replaced by your backend) |
| `src/state/session.tsx` | `features/auth/application/session_controller.dart` |
| `src/state/data.tsx` | `features/commitments/application/commitments_controller.dart` |
| `src/state/preferences.tsx` | `features/settings/application/preferences_controller.dart` |
| `src/state/reminders.tsx` | `features/reminders/application/reminder_providers.dart` |
| `src/screens/AuthScreen.tsx` | `features/auth/presentation/auth_screen.dart` |
| `app/reset-password.tsx` | `features/auth/presentation/reset_password_screen.dart` |
| `src/screens/FocusScreen.tsx` | `features/commitments/presentation/screens/focus_screen.dart` |
| `src/screens/CreateCommitment.tsx` | `.../screens/create_commitment_screen.dart` + `pace_editor_modal.dart` + `data/draft_store.dart` |
| `app/(app)/commitment/[id].tsx` | `.../screens/commitment_detail_screen.dart` |
| `app/(app)/commitment/reflect.tsx` | `.../screens/reflection_screen.dart` |
| `app/(app)/(tabs)/history.tsx` | `.../screens/history_screen.dart` |
| `app/(app)/(tabs)/settings.tsx` | `features/settings/presentation/settings_screen.dart` |
| `app/(app)/tracking.tsx`, `commitments.tsx` | `.../screens/tracking_screen.dart`, `commitments_list_screen.dart` |
| `app/(app)/(tabs)/_layout.tsx` (tab bar) | `app/tab_shell.dart` |
| `app/_layout.tsx`, expo-router file routes | `app/app.dart`, `app/router.dart` |
| `tests/*.test.ts` | `test/domain/*_test.dart` (ported, 34 tests) |

## Concept cheat-sheet

| In React Native | In Flutter | Notes |
| --- | --- | --- |
| Component (function returning JSX) | `Widget` class with a `build()` method | Everything is a widget, including padding and alignment |
| `useState` | `StatefulWidget` + `setState`, or a Riverpod `Notifier` | Local UI state → `setState`; shared state → Riverpod |
| `useContext` / providers | Riverpod providers + `ref.watch` | |
| `useEffect` | `initState`/`dispose`, `ref.listen`, or an "effect" provider | e.g. `reminderSyncProvider` |
| `StyleSheet`, flex styles | Widget properties + `Row`/`Column`/`Padding`/`Container` | `gap` ➜ `spacing:` on Row/Column |
| `Pressable` | `GestureDetector` (our `Tappable`) | No ripple: matches the design |
| `ScrollView` | `CustomScrollView` / `SingleChildScrollView` | `AppScreen` wraps it |
| `Modal` (declarative `visible`) | `showGeneralDialog` (imperative, awaited) | `showAppModal` |
| `Animated` / Reanimated | Implicit animations (`AnimatedContainer`, `TweenAnimationBuilder`) | No manual "shared values" |
| `expo-router` files | `go_router` route table | `app/router.dart` |
| AsyncStorage | `shared_preferences` (data), `flutter_secure_storage` (tokens) | |
| expo-haptics | `HapticFeedback` | |
| expo-notifications | `flutter_local_notifications` | |
| Feather icons (`@expo/vector-icons`) | the same `Feather.ttf`, wrapped in `core/widgets/feather_icons.dart` | pixel-identical |
| Inter via `@expo-google-fonts` | the same TTF files bundled in `assets/fonts/` | |
| `@clerk/expo` | `clerk_flutter` / `clerk_auth` (beta) wrapped by `ClerkAuthGateway` | |
| Supabase client | removed | replaced later by your NestJS API |

## Intentional differences (and why)

* **Clerk UI.** The sign-in/up/reset screens are still the app's own custom
  screens. They call Clerk's SDK through `ClerkAuthGateway`; we do *not* use
  Clerk's prebuilt Flutter widgets (they would not match the design).
* **Reset password** collects the code and the new password on separate steps
  (as in the design), but Clerk's Flutter SDK verifies them in one request, so
  a wrong code is reported on the last step and the user is returned to the
  code step.
* **Google sign-in** uses Clerk's built-in web-view flow instead of an Expo
  browser session. The `/sso-callback` and `/auth/callback` placeholder routes of
  the old app are not needed.
* **Signed-in data is stored on the device, per account**, until the backend
  exists (the RN app kept Clerk users' data in Supabase). Signing out does *not*
  erase it.
* **Haptics**: Flutter offers impact strengths rather than "success/warning"
  notification patterns; success ➜ medium impact, warning ➜ heavy impact.
* **List animations**: new rows fade in and changing cards animate their size;
  rows do not animate sliding when siblings are removed.
* **Notifications** use inexact scheduling (may arrive a few minutes late), which
  needs no special Android permission. The "development build required" note of
  the Expo version no longer applies: it works in any build.
* **Settings** has no "Expo Go" caveats.
