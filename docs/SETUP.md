# Setup, running, and releasing

## 1. Prerequisites

* Flutter 3.44+ (`flutter --version`) and `flutter doctor` green for the platform
  you target.
* iOS: Xcode + an Apple Developer account for devices/TestFlight.
* Android: Android Studio / SDK, and `flutter doctor --android-licenses` accepted.

## 2. Configuration (keys)

The app reads build-time values with `--dart-define`; nothing secret is stored
in source control.

```sh
cp env/dev.example.json env/dev.json     # env/*.json is git-ignored
# edit env/dev.json
flutter run --dart-define-from-file=env/dev.json
```

| Key | Meaning |
| --- | --- |
| `CLERK_PUBLISHABLE_KEY` | `pk_test_...` / `pk_live_...` from the Clerk dashboard (public by design) |
| `API_URL` | LockIn API base URL, no trailing slash (default: Render production API) |
| `ENABLE_DEVICE_MODE` | legacy offline shortcut; leave `false` with the API because all API calls require Clerk |

> Never put a Clerk **secret** key, database URL or any private credential in
> the app. Everything inside an app binary can be extracted.

Use the same Clerk application as the web app. A token from another Clerk
instance will be rejected by the API. The app fetches a fresh session token for
every request; never add a token to `env/*.json` or persist it yourself.

`API_BASE_URL` is accepted temporarily as a compatibility fallback, but new
configuration should use `API_URL`.

## 3. Clerk dashboard settings

Docs: <https://clerk.com/docs> and the SDK page <https://pub.dev/packages/clerk_flutter>.

1. Create an application in Clerk and copy the **publishable key**.
2. **Native applications**: in *Configure → Native applications* enable the
   Native API for your instance (required for mobile SDKs).
3. **Email, password**: enable *Email address* + *Password* sign-in, and *Email
   verification code* (the app uses a 6-digit code).
4. **Google**: enable the Google social connection. For production create your
   own Google OAuth credentials (the Clerk shared dev credentials only work for
   development).
5. If you enable *legal consent* ("accept terms") or *MFA*, the current custom
   screens will report that extra steps are required; those flows are not built
   yet.

> The Clerk Flutter SDK is **beta** (0.0.x): its API can change between
> versions. That is why it is wrapped by `ClerkAuthGateway`; if an update breaks
> something, you only fix that one file.

## 4. Running

```sh
flutter run -d <device-id>        # list devices with: flutter devices
flutter test                      # business-rule tests
flutter analyze                   # static analysis (should print "No issues found")
```

## 5. App identifiers

Both stores use the same id as the old app: `com.lockin.habits`
(Android `applicationId`, iOS bundle identifier). Change them before your first
upload if you want a different one:

* Android: `android/app/build.gradle.kts` (`applicationId`, `namespace`) and the
  folder/`package` line of `MainActivity.kt`.
* iOS: Xcode → Runner → Signing & Capabilities → Bundle Identifier.

## 6. Before the first store release (checklist)

* [ ] **App icon & splash**: replace the default Flutter icon (e.g. with the
      `flutter_launcher_icons` and `flutter_native_splash` packages).
* [ ] **Android signing**: create an upload keystore (back it up; losing it
      means you can't ship updates without contacting Google):
      `keytool -genkey -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.
      Copy `android/key.properties.example` to `android/key.properties` and fill
      in the passwords. `build.gradle.kts` uses it automatically and falls back
      to debug keys (with a warning) when it is missing.
* [ ] **Android builds**: always build through `scripts/build_android.sh` so
      the env file is never forgotten (a build without it has sign-in
      disabled). `scripts/build_android.sh` makes small per-CPU test APKs;
      `scripts/build_android.sh prod aab` makes the Play Store bundle.
* [ ] **iOS signing**: set your Team in Xcode, build with
      `flutter build ipa --dart-define-from-file=env/prod.json`.
* [ ] `ENABLE_DEVICE_MODE=false` in the production env file.
* [ ] Switch Clerk to a **production instance** and its `pk_live_` key.
* [ ] Privacy: both stores ask what data you collect; with Clerk this includes
      email address and identifiers. Add a privacy-policy URL.
* [ ] Bump `version:` in `pubspec.yaml` (`1.0.1+2`: the number after `+` must
      increase for every upload).
* [ ] Test notifications on a real Android 13+ device and a real iPhone.
