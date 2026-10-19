/// [AuthGateway] implemented with Clerk's Flutter SDK (`clerk_flutter` /
/// `clerk_auth`).
///
/// Docs: https://clerk.com/docs and https://pub.dev/packages/clerk_flutter
///
/// ## How Clerk's sign-in model works (important to understand)
///
/// Clerk models authentication as a *state machine* held in a "client" object.
/// You do not call "login(email, password)" and get a token back. Instead you
/// call `attemptSignIn` / `attemptSignUp` repeatedly with whatever the current
/// step needs, and after each call you inspect the client:
///
/// * `isSignedIn` – done, a session exists.
/// * `signUp` still present with unverified fields – a code must be verified.
///
/// The SDK object, [ClerkAuthState], is a `ChangeNotifier`, so the app can
/// react when the state changes.
library;

import 'dart:async';

import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/widgets.dart';

import 'auth_gateway.dart';
import 'secure_clerk_persistor.dart';

/// Clerk-backed authentication.
class ClerkAuthGateway extends ChangeNotifier implements AuthGateway {
  ClerkAuthGateway._(this.clerkState) {
    clerkState.addListener(notifyListeners);
  }

  /// Initialises the Clerk SDK (network call to fetch your instance's
  /// settings) and returns the gateway.
  static Future<ClerkAuthGateway> create(String publishableKey) async {
    final state = await ClerkAuthState.create(
      config: ClerkAuthConfig(
        publishableKey: publishableKey,
        persistor: SecureClerkPersistor(),
        // Skip the SDK's built-in loading overlay animation widget; we show
        // our own splash while it initialises.
        loading: const SizedBox.shrink(),
      ),
    );
    return ClerkAuthGateway._(state);
  }

  /// The underlying SDK object. The app root hands it to the `ClerkAuth`
  /// widget, which Clerk's web-view based Google sign-in needs.
  final ClerkAuthState clerkState;

  @override
  bool get isConfigured => true;

  @override
  AuthUser? get currentUser {
    final user = clerkState.user;
    if (user == null) return null;
    return AuthUser(id: user.id, name: user.name, email: user.email);
  }

  @override
  void dispose() {
    clerkState.removeListener(notifyListeners);
    super.dispose();
  }

  /// Runs [action], converting any Clerk/network error to a friendly
  /// [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action, String fallback) async {
    try {
      return await action();
    } on clerk.ClerkError catch (e) {
      throw AuthFailure(_messageFor(e, fallback));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw AuthFailure(fallback);
    }
  }

  /// Clerk's server errors carry a human sentence ("Password is incorrect.").
  /// Prefer it; otherwise fall back to our own wording.
  String _messageFor(clerk.ClerkError error, String fallback) {
    final first = error.errors?.errors?.firstOrNull;
    final detail = first?.longMessage ?? first?.message;
    if (detail != null && detail.isNotEmpty) return detail;
    return fallback;
  }

  @override
  Future<void> signInWithPassword({required String email, required String password}) =>
      _guard(() async {
        await clerkState.attemptSignIn(
          strategy: clerk.Strategy.password,
          identifier: email,
          password: password,
        );
        if (!clerkState.isSignedIn) {
          // e.g. the account requires a second factor, which this app's UI
          // does not implement yet.
          throw const AuthFailure(
            'Additional verification is required for this account, which this '
            'version of LockIn does not support yet.',
          );
        }
      }, 'Could not sign in. Check your email and password, then retry.');

  @override
  Future<SignUpOutcome> signUp({required String email, required String password}) =>
      _guard(() async {
        // Step 1: create the sign-up with email + password.
        await clerkState.attemptSignUp(
          strategy: clerk.Strategy.password,
          emailAddress: email,
          password: password,
          passwordConfirmation: password,
        );
        if (clerkState.isSignedIn) return SignUpOutcome.signedIn;
        // Step 2: ask Clerk to email the verification code.
        await clerkState.attemptSignUp(strategy: clerk.Strategy.emailCode);
        return SignUpOutcome.needsEmailCode;
      }, 'Could not create your account. Check your details and try again.');

  @override
  Future<void> verifyEmailCode(String code) => _guard(() async {
        await clerkState.attemptSignUp(strategy: clerk.Strategy.emailCode, code: code);
        if (!clerkState.isSignedIn) {
          throw const AuthFailure('That code could not be verified. Try again.');
        }
      }, 'That code could not be verified. Try again.');

  @override
  Future<void> resendEmailCode() => _guard(
        () async {
          await clerkState.resendCode(clerk.Strategy.emailCode);
        },
        'Could not resend the code. Please retry.',
      );

  @override
  Future<void> signInWithGoogle(BuildContext context) async {
    clerk.ClerkError? failure;
    try {
      // Opens Clerk's web view for Google, then completes the session.
      await clerkState.ssoSignIn(
        context,
        clerk.Strategy.oauthGoogle,
        onError: (error) => failure = error,
      );
    } catch (_) {
      throw const AuthFailure('Google sign-in could not finish. Please try again.');
    }
    final error = failure;
    if (error != null) {
      throw AuthFailure(_messageFor(error, 'Google sign-in could not finish. Please try again.'));
    }
  }

  @override
  Future<void> requestPasswordReset(String email) => _guard(() async {
        await clerkState.initiatePasswordReset(
          identifier: email,
          strategy: clerk.Strategy.resetPasswordEmailCode,
        );
      }, 'Could not send a reset code. Please retry.');

  @override
  Future<void> completePasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _guard(() async {
        // Clerk verifies the emailed code and sets the new password in one call.
        await clerkState.attemptSignIn(
          strategy: clerk.Strategy.resetPasswordEmailCode,
          identifier: email,
          password: newPassword,
          code: code,
        );
        if (!clerkState.isSignedIn) {
          throw const AuthFailure('That code is not valid. Check it and try again.');
        }
      }, 'Could not reset your password. Please retry.');

  @override
  Future<void> signOut() => _guard(clerkState.signOut, 'Could not sign out. Please try again.');

  @override
  Future<String?> sessionToken() async {
    if (!clerkState.isSignedIn) return null;
    final token = await clerkState.sessionToken();
    return token.jwt;
  }
}
