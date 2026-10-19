/// "Who is using the app right now?"
///
/// Combines two sources into one [Identity]:
///
/// * **cloud** – signed in through Clerk;
/// * **device** – the "Continue on this device" shortcut (a local test mode,
///   switched off for store builds with `ENABLE_DEVICE_MODE=false`).
///
/// The rest of the app only looks at [sessionProvider]. Routing uses it to
/// decide between the sign-in screens and the app; the data layer uses
/// `identity.key` to keep each account's data separate.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../reminders/application/reminder_providers.dart';
import '../data/auth_gateway.dart';
import '../data/clerk_auth_gateway.dart';
import '../data/disabled_auth_gateway.dart';

/// Where the identity comes from.
enum IdentityMode { device, cloud }

/// The current user.
class Identity {
  /// Creates an identity.
  const Identity({required this.key, required this.mode, this.name = '', this.email});

  /// Unique, stable id; used in storage keys (`device` or the Clerk user id).
  final String key;

  /// Device shortcut or real account.
  final IdentityMode mode;

  /// Display name (may be empty).
  final String name;

  /// Email (cloud accounts).
  final String? email;
}

/// Session state.
class SessionState {
  /// Creates a state.
  const SessionState({this.identity, this.loading = false, this.error});

  /// The user, or `null` when signed out.
  final Identity? identity;

  /// True while the auth SDK is still starting.
  final bool loading;

  /// A start-up/auth problem to display on the sign-in screen.
  final String? error;
}

/// Creates the auth gateway once: Clerk when a key is configured, otherwise a
/// disabled stand-in so the app still runs.
final authGatewayProvider = FutureProvider<AuthGateway>((ref) async {
  if (!AppConfig.hasClerk) return DisabledAuthGateway();
  final gateway = await ClerkAuthGateway.create(AppConfig.clerkPublishableKey);
  ref.onDispose(gateway.dispose);
  return gateway;
});

const _deviceSessionKey = 'lockin.device-session.v1';

/// Owns the [SessionState].
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final gatewayAsync = ref.watch(authGatewayProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final deviceFlag = AppConfig.enableDeviceMode && (prefs.getBool(_deviceSessionKey) ?? false);

    return gatewayAsync.when(
      loading: () => const SessionState(loading: true),
      error: (error, _) => SessionState(
        identity: deviceFlag ? const Identity(key: 'device', mode: IdentityMode.device) : null,
        error: 'Could not reach the sign-in service. Check your connection and restart.',
      ),
      data: (gateway) {
        // Re-evaluate whenever Clerk's sign-in state changes. `invalidateSelf`
        // re-runs this method; the listener is removed on every dispose.
        void onAuthChanged() => ref.invalidateSelf();
        gateway.addListener(onAuthChanged);
        ref.onDispose(() => gateway.removeListener(onAuthChanged));

        final user = gateway.currentUser;
        if (user != null) {
          // A real account replaces the device shortcut.
          if (deviceFlag) unawaited(prefs.remove(_deviceSessionKey));
          return SessionState(
            identity: Identity(
              key: user.id,
              mode: IdentityMode.cloud,
              name: user.name,
              email: user.email,
            ),
          );
        }
        return SessionState(
          identity: deviceFlag ? const Identity(key: 'device', mode: IdentityMode.device) : null,
        );
      },
    );
  }

  /// "Continue on this device".
  Future<void> enterDevice() async {
    await ref.read(sharedPreferencesProvider).setBool(_deviceSessionKey, true);
    ref.invalidateSelf();
  }

  /// Signs out of Clerk (if needed) and forgets the device shortcut.
  ///
  /// Scheduled reminders are cancelled first so a signed-out phone never
  /// buzzes about someone's habits.
  Future<void> signOut() async {
    await clearReminders(ref);
    final identity = state.identity;
    if (identity?.mode == IdentityMode.cloud) {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.signOut();
    }
    await ref.read(sharedPreferencesProvider).remove(_deviceSessionKey);
    ref.invalidateSelf();
  }
}

/// The current session.
final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
