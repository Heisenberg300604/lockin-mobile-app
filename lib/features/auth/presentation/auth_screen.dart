/// Sign-in and sign-up (one screen, two modes) matching reference image 1.
///
/// Flow for **sign-up**: email + password → "we emailed you a code" →
/// enter the 6-digit code → signed in. Flow for **sign-in**: email + password
/// → signed in. After either, the session provider changes and the router
/// automatically moves to the Focus tab; this screen does not navigate itself.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/containers.dart';
import '../../../core/widgets/lock_button.dart';
import '../../../core/widgets/modal_card.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../core/widgets/tappable.dart';
import '../../../core/widgets/typography.dart';
import '../application/session_controller.dart';
import '../data/auth_gateway.dart';
import 'google_logo.dart';

/// `/sign-in` and `/sign-up`.
class AuthScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [signUp] switches to the create-account variant.
  const AuthScreen({super.key, this.signUp = false});

  /// True for the sign-up variant.
  final bool signUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  String _email = '';
  String _password = '';
  String _confirm = '';
  String _code = '';
  bool _awaitingCode = false;
  bool _busy = false;
  String _error = '';
  String _message = '';

  static final _emailPattern = RegExp(r'^\S+@\S+\.\S+$');

  AuthGateway? get _gateway => ref.read(authGatewayProvider).value;

  /// Runs [action] with the busy flag and error handling shared by all buttons.
  Future<void> _run(Future<void> Function(AuthGateway gateway) action) async {
    final gateway = _gateway;
    if (gateway == null) {
      setState(() => _error = 'Sign-in is not available right now. Please restart the app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _message = '';
    });
    try {
      await action(gateway);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_awaitingCode) {
      if (!RegExp(r'^\d{6}$').hasMatch(_code.trim())) {
        setState(() => _error = 'Enter the 6-digit code from your email.');
        return;
      }
      return _run((g) => g.verifyEmailCode(_code.trim()));
    }
    if (!_emailPattern.hasMatch(_email.trim())) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_password.length < 8) {
      setState(() => _error = 'Use a password with at least 8 characters.');
      return;
    }
    if (widget.signUp && _password != _confirm) {
      setState(() => _error = 'Your passwords do not match.');
      return;
    }
    return _run((g) async {
      if (widget.signUp) {
        final outcome = await g.signUp(email: _email.trim(), password: _password);
        if (outcome == SignUpOutcome.needsEmailCode && mounted) {
          setState(() {
            _awaitingCode = true;
            _message = 'We sent a 6-digit verification code to your email.';
          });
        }
      } else {
        await g.signInWithPassword(email: _email.trim(), password: _password);
      }
    });
  }

  Future<void> _google() => _run((g) => g.signInWithGoogle(context));

  Future<void> _device() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).enterDevice();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open local storage. Please try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final signUp = widget.signUp;
    final sessionError = ref.watch(sessionProvider.select((s) => s.error));
    final shownError = _error.isNotEmpty ? _error : sessionError;

    return AppScreen(
      setup: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        // Brand + language selector
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Brand(),
              Tappable(
                semanticLabel: 'Language',
                onTap: () => showAppModal<void>(
                  context,
                  builder: (ctx) => ModalCard(
                    title: 'Language',
                    children: [
                      LockButton(light: true, title: 'English ✓', onPressed: () => Navigator.of(ctx).pop()),
                    ],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfacePanel,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Label('◎ English⌄', size: 12),
                ),
              ),
            ],
          ),
        ),
        // Heading (takes the free space and sits at its bottom)
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: signUp ? 80 : 170),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 44),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ScreenTitle(signUp ? 'Start a new promise.' : 'Ready to Lock In?', align: TextAlign.center),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Label(
                      signUp
                          ? 'Build your focus. Keep a promise to yourself.'
                          : 'Authenticate your credentials to access your parameters, lock focus, and secure your active streaks.',
                      color: AppColors.inkSecondary,
                      align: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Form panel
        AppCard(
          color: AppColors.surfacePanel,
          radius: 36,
          padding: const EdgeInsets.all(24),
          edge: const EdgeInsets.only(bottom: 1, left: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              if (_awaitingCode)
                AppField(
                  pill: true,
                  placeholder: '6-digit verification code',
                  value: _code,
                  onChanged: (v) => _code = v,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                )
              else ...[
                AppField(
                  pill: true,
                  placeholder: 'Email',
                  value: _email,
                  onChanged: (v) => _email = v,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                AppField(
                  pill: true,
                  placeholder: 'Password',
                  value: _password,
                  onChanged: (v) => _password = v,
                  obscure: true,
                  autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                ),
                if (signUp)
                  AppField(
                    pill: true,
                    placeholder: 'Confirm password',
                    value: _confirm,
                    onChanged: (v) => _confirm = v,
                    obscure: true,
                  ),
              ],
              if (shownError != null && shownError.isNotEmpty) ErrorNote(shownError),
              if (_message.isNotEmpty)
                Label(_message, size: 13, color: AppColors.successForeground),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LockButton(
                  title: _awaitingCode
                      ? 'VERIFY EMAIL'
                      : signUp
                          ? 'START MY PROMISE'
                          : 'ENTER FOCUS MODE',
                  loading: _busy,
                  onPressed: () => unawaited(_submit()),
                ),
              ),
              if (!_awaitingCode)
                Tappable(
                  isButton: false,
                  onTap: () => context.go(signUp ? '/sign-in' : '/sign-up'),
                  child: Text.rich(
                    textAlign: TextAlign.center,
                    TextSpan(
                      style: AppText.style(size: 12),
                      children: [
                        TextSpan(text: signUp ? 'Already have an account? ' : 'New here? '),
                        TextSpan(
                          text: signUp ? 'Sign in.' : 'Start a new promise.',
                          style: AppText.style(size: 12, underline: true),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!signUp && AppConfig.hasClerk)
                Tappable(
                  isButton: false,
                  onTap: () => context.push('/reset-password'),
                  child: const Label('Forgot password?', size: 12, underline: true, align: TextAlign.center),
                ),
              if (!_awaitingCode)
                const Row(
                  spacing: 24,
                  children: [
                    Expanded(child: SizedBox(height: 1, child: ColoredBox(color: AppColors.surfaceCard))),
                    Label('OR', size: 11, muted: true),
                    Expanded(child: SizedBox(height: 1, child: ColoredBox(color: AppColors.surfaceCard))),
                  ],
                ),
              if (!_awaitingCode)
                Tappable(
                  semanticLabel: 'Continue with Google',
                  enabled: !_busy,
                  onTap: () => unawaited(_google()),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: const [
                        BoxShadow(color: AppColors.softShadow, offset: Offset(0, 4), blurRadius: 3),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 10,
                      children: [
                        GoogleLogo(),
                        Label('Continue with Google', size: 13, bold: true),
                      ],
                    ),
                  ),
                ),
              if (!_awaitingCode && AppConfig.enableDeviceMode) ...[
                Tappable(
                  semanticLabel: 'Continue on this device',
                  enabled: !_busy,
                  onTap: () => unawaited(_device()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Label('Continue on this device', size: 12, underline: true, align: TextAlign.center),
                  ),
                ),
                const Label('Your commitments stay on this device.', size: 11, muted: true, align: TextAlign.center),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
