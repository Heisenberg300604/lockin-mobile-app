/// Password reset: email → code → new password → done.
///
/// Clerk checks the emailed code and sets the new password in a single call,
/// so the code is collected on its own step but verified together with the
/// password. If Clerk rejects the code, we bring the user back to the code step.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/containers.dart';
import '../../../core/widgets/lock_button.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../core/widgets/typography.dart';
import '../application/session_controller.dart';
import '../data/auth_gateway.dart';

enum _Step { email, code, password, done }

/// `/reset-password`.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  _Step _step = _Step.email;
  String _email = '';
  String _code = '';
  String _password = '';
  String _confirm = '';
  bool _busy = false;
  String _error = '';

  Future<void> _submit() async {
    setState(() => _error = '');
    if (_step == _Step.email && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.trim())) {
      return setState(() => _error = 'Enter your email address.');
    }
    if (_step == _Step.code && !RegExp(r'^\d{6}$').hasMatch(_code.trim())) {
      return setState(() => _error = 'Enter the 6-digit code from your email.');
    }
    if (_step == _Step.password && (_password.length < 8 || _password != _confirm)) {
      return setState(() => _error = 'Use matching passwords with at least 8 characters.');
    }
    final gateway = ref.read(authGatewayProvider).value;
    if (gateway == null) {
      return setState(() => _error = 'Sign-in is not available right now. Please restart the app.');
    }
    setState(() => _busy = true);
    try {
      switch (_step) {
        case _Step.email:
          await gateway.requestPasswordReset(_email.trim());
          setState(() => _step = _Step.code);
        case _Step.code:
          setState(() => _step = _Step.password);
        case _Step.password:
          try {
            await gateway.completePasswordReset(
              email: _email.trim(),
              code: _code.trim(),
              newPassword: _password,
            );
            setState(() => _step = _Step.done);
          } on AuthFailure catch (e) {
            // Most likely a wrong/expired code: let the user retype it.
            setState(() {
              _step = _Step.code;
              _error = e.message;
            });
          }
        case _Step.done:
          break;
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not finish this request. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.email => 'Reset your password',
      _Step.code => 'Check your email',
      _Step.password => 'Set a new password',
      _Step.done => 'Password updated',
    };
    final action = switch (_step) {
      _Step.email => 'SEND RESET CODE',
      _Step.code => 'VERIFY CODE',
      _Step.password => 'UPDATE PASSWORD',
      _Step.done => 'CONTINUE',
    };
    return AppScreen(
      setup: true,
      header: AppHeader(
        back: true,
        onBack: () => context.canPop() ? context.pop() : context.go('/sign-in'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenTitle(title),
              const SizedBox(height: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  if (_step == _Step.email)
                    AppField(
                      label: 'Email',
                      value: _email,
                      onChanged: (v) => _email = v,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  if (_step == _Step.code) ...[
                    Label('Enter the 6-digit code sent to ${_email.trim()}.'),
                    AppField(
                      label: 'Verification code',
                      value: _code,
                      onChanged: (v) => _code = v,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  if (_step == _Step.password) ...[
                    AppField(
                      label: 'New password',
                      value: _password,
                      onChanged: (v) => _password = v,
                      obscure: true,
                    ),
                    AppField(
                      label: 'Confirm password',
                      value: _confirm,
                      onChanged: (v) => _confirm = v,
                      obscure: true,
                    ),
                  ],
                  if (_error.isNotEmpty) ErrorNote(_error),
                  LockButton(
                    title: action,
                    loading: _busy,
                    onPressed: () => _step == _Step.done ? context.go('/') : unawaited(_submit()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
