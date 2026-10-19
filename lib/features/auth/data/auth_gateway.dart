/// What the rest of the app needs from an authentication provider.
///
/// Screens never import Clerk directly. They talk to [AuthGateway]. This keeps
/// the vendor in one folder: if you ever switch provider, or Clerk's beta SDK
/// changes its API (it is allowed to until 1.0), only `clerk_auth_gateway.dart`
/// changes. It also lets tests use a fake gateway.
library;

import 'package:flutter/widgets.dart';

/// The signed-in person, reduced to what the UI shows.
class AuthUser {
  /// Creates an auth user.
  const AuthUser({required this.id, required this.name, this.email});

  /// Stable id from the provider (used to separate stored data per account).
  final String id;

  /// Display name; may be empty.
  final String name;

  /// Primary email, if known.
  final String? email;
}

/// A problem to show the user (wrong password, bad code, no network, ...).
/// [message] is already friendly.
class AuthFailure implements Exception {
  /// Creates a failure.
  const AuthFailure(this.message);

  /// Text safe to show in the UI.
  final String message;

  @override
  String toString() => message;
}

/// Result of starting a sign-up.
enum SignUpOutcome {
  /// The account was created and the user is signed in.
  signedIn,

  /// A verification code was emailed; call [AuthGateway.verifyEmailCode].
  needsEmailCode,
}

/// Authentication operations. Also a [Listenable]: it notifies when the
/// signed-in state changes (sign-in, sign-out, token expiry elsewhere).
abstract interface class AuthGateway implements Listenable {
  /// False when no Clerk key was provided: sign-in is unavailable.
  bool get isConfigured;

  /// The signed-in user, or `null`.
  AuthUser? get currentUser;

  /// Email + password sign-in.
  Future<void> signInWithPassword({required String email, required String password});

  /// Creates an account with email + password and emails a verification code.
  Future<SignUpOutcome> signUp({required String email, required String password});

  /// Completes sign-up with the 6-digit emailed [code].
  Future<void> verifyEmailCode(String code);

  /// Resends the sign-up verification code.
  Future<void> resendEmailCode();

  /// Google sign-in. Needs a [context] because the provider shows a web view.
  Future<void> signInWithGoogle(BuildContext context);

  /// Emails a password-reset code to [email].
  Future<void> requestPasswordReset(String email);

  /// Verifies the reset [code] and sets [newPassword]. Signs the user in.
  Future<void> completePasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Signs out of the provider.
  Future<void> signOut();

  /// A fresh session token (JWT) to send to your backend as
  /// `Authorization: Bearer <token>`, or `null` when signed out.
  Future<String?> sessionToken();
}
