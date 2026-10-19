/// App-wide dependency providers.
///
/// ## Riverpod in 60 seconds
///
/// A *provider* is a named, lazily created, cached value that any widget or
/// other provider can read. Providers can depend on one another:
/// `ref.watch(x)` means "rebuild me when x changes".
///
/// Why this helps: instead of passing objects down through constructors or
/// using global variables, anything needs `ref.watch(thing)`. In tests you can
/// *override* any provider with a fake. See `docs/ARCHITECTURE.md`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'config/app_config.dart';
import 'network/api_client.dart';
import '../features/auth/application/session_controller.dart';
import '../features/commitments/data/key_value_store.dart';

/// The initialised [SharedPreferences]. It is created before `runApp` (it is
/// asynchronous) and injected in `main.dart` with `overrideWithValue`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

/// Simple string storage on top of [sharedPreferencesProvider].
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SharedPreferencesStore(ref.watch(sharedPreferencesProvider)),
);

/// The source of "now". Tests override this to control time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Generates unique ids (v4 UUIDs) for idempotency "request ids".
final uuidProvider = Provider<String Function()>((ref) {
  const uuid = Uuid();
  return uuid.v4;
});

/// API client shared by the remote repositories. The callback asks Clerk for
/// a fresh short-lived JWT immediately before every HTTP request.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () async {
      final gateway = await ref.read(authGatewayProvider.future);
      return gateway.sessionToken();
    },
  ),
);
