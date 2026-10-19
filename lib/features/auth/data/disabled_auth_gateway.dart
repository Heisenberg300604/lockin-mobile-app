/// Used when no Clerk key is configured, so the app still runs (device mode
/// only) while you are setting things up.
library;

import 'package:flutter/widgets.dart';

import 'auth_gateway.dart';

/// An [AuthGateway] that is never signed in and rejects every operation with a
/// friendly message.
class DisabledAuthGateway extends ChangeNotifier implements AuthGateway {
  static const _message =
      'Sign-in is not set up yet. Add your Clerk key (see docs/SETUP.md).';

  @override
  bool get isConfigured => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Future<void> signInWithPassword({required String email, required String password}) =>
      Future.error(const AuthFailure(_message));

  @override
  Future<SignUpOutcome> signUp({required String email, required String password}) =>
      Future.error(const AuthFailure(_message));

  @override
  Future<void> verifyEmailCode(String code) => Future.error(const AuthFailure(_message));

  @override
  Future<void> resendEmailCode() => Future.error(const AuthFailure(_message));

  @override
  Future<void> signInWithGoogle(BuildContext context) =>
      Future.error(const AuthFailure(_message));

  @override
  Future<void> requestPasswordReset(String email) => Future.error(const AuthFailure(_message));

  @override
  Future<void> completePasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      Future.error(const AuthFailure(_message));

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> sessionToken() async => null;
}
