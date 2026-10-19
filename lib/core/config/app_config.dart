/// Build-time configuration (keys and switches).
///
/// Values are injected when you build/run, **not** hard-coded, so secrets and
/// per-environment settings never live in source control:
///
/// ```sh
/// flutter run --dart-define-from-file=env/dev.json
/// ```
///
/// See `env/dev.example.json` and `docs/SETUP.md`. Only *public* keys belong in
/// a mobile app (Clerk's publishable key is public by design). Never put a
/// secret key (Clerk secret key, database passwords, ...) in here: anything in
/// the app binary can be extracted by users.
library;

/// App-wide configuration constants.
abstract final class AppConfig {
  /// Clerk publishable key (`pk_test_...` / `pk_live_...`).
  ///
  /// When empty, authentication is disabled and only "Continue on this device"
  /// is available, so the app is still runnable before you have a key.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  /// Base URL of the LockIn API, without a trailing slash.
  ///
  /// `API_URL` is the documented name. `API_BASE_URL` remains as a temporary
  /// fallback so existing local developer configuration does not silently
  /// stop working.
  static const _documentedApiUrl = String.fromEnvironment('API_URL');
  static const _legacyApiUrl = String.fromEnvironment('API_BASE_URL');
  static String get apiBaseUrl => _documentedApiUrl.isNotEmpty
      ? _documentedApiUrl
      : (_legacyApiUrl.isNotEmpty
            ? _legacyApiUrl
            : 'https://lockin-a0os.onrender.com/api/v1');

  /// Whether the "Continue on this device" shortcut is offered on the sign-in
  /// screen. The original app shipped it for local testing. Set
  /// `--dart-define=ENABLE_DEVICE_MODE=false` for store builds.
  static const enableDeviceMode = bool.fromEnvironment(
    'ENABLE_DEVICE_MODE',
    defaultValue: false,
  );

  /// True when a Clerk key was provided.
  static bool get hasClerk => clerkPublishableKey.isNotEmpty;

  /// Version string shown in Settings.
  static const appVersion = '0.1.0';
}
