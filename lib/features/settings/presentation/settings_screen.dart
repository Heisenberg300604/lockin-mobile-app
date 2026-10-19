/// Settings tab: account, motion/haptics, reminders, sign-out.
library;

import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart' show Switch;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/motion/reduced_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_screen.dart';
import '../../../core/widgets/containers.dart';
import '../../../core/widgets/feather_icons.dart';
import '../../../core/widgets/lock_button.dart';
import '../../../core/widgets/modal_card.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../core/widgets/typography.dart';
import '../../auth/application/session_controller.dart';
import '../../commitments/domain/models.dart';
import '../../reminders/application/reminder_providers.dart';
import '../application/preferences_controller.dart';

/// The Settings tab.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late String _time = ref.read(preferencesProvider).preferences.reminderTime;
  bool _saving = false;
  String _message = '';
  String _error = '';

  /// Runs a preference change with the shared saving/error handling.
  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = '';
      _message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is LockInException ? e.message : 'Your preference was not saved. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleReminders(bool enabled) => _save(() async {
        final service = ref.read(notificationServiceProvider);
        if (enabled && !await service.permission(request: true)) {
          throw const LockInException('Allow notifications in your device settings, then try again.');
        }
        if (!enabled) await ref.read(reminderSchedulerProvider).sync(const []);
        await ref.read(preferencesProvider.notifier).update(reminders: enabled);
      });

  Future<void> _confirmSignOut(bool device) async {
    await showAppModal<void>(
      context,
      builder: (_) => _SignOutModal(device: device),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefsState = ref.watch(preferencesProvider);
    final prefs = prefsState.preferences;
    final ready = prefsState.ready;
    final reduced = ref.watch(reducedMotionProvider);
    final identity = ref.watch(sessionProvider.select((s) => s.identity));
    final status = ref.watch(reminderStatusProvider);
    final device = identity?.mode == IdentityMode.device;
    final controller = ref.read(preferencesProvider.notifier);

    return AppScreen(
      header: const AppHeader(),
      gap: 24,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const SectionLabel('Settings'),
        // ---- Account -----------------------------------------------------------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 16,
                children: [
                  const AppIcon(Feather.user, size: 32),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Label(
                          device
                              ? 'On this device'
                              : (identity?.name.isNotEmpty ?? false)
                                  ? identity!.name
                                  : 'Your account',
                          bold: true,
                          size: 19,
                        ),
                        Label(
                          identity?.email ?? (device ? 'Saved locally. No account required.' : 'Signed in'),
                          size: 13,
                          muted: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const AppDivider(),
              Label(
                device
                    ? 'Your commitments are stored on this device and are not synced to an account.'
                    : 'Your commitments are private to your account.',
                size: 13,
                muted: true,
              ),
            ],
          ),
        ),
        // ---- Motion & accessibility ----------------------------------------------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Label('Motion & accessibility', bold: true),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Label(
                  'LockIn follows your device’s reduced motion and text size settings.',
                  size: 13,
                  muted: true,
                ),
              ),
              _SwitchRow(
                label: 'Reduce motion',
                value: prefs.motion == MotionPreference.reduced,
                enabled: ready && !_saving,
                onChanged: (v) => _save(
                  () => controller.update(motion: v ? MotionPreference.reduced : MotionPreference.system),
                ),
              ),
              Label(
                reduced ? 'Reduced motion is active.' : 'Following your device settings.',
                muted: true,
                size: 12,
              ),
              _SwitchRow(
                label: 'Haptic feedback',
                value: prefs.haptics,
                enabled: ready && !_saving,
                onChanged: (v) => _save(() => controller.update(haptics: v)),
              ),
              const Label('Gentle feedback for choices and saved progress.', muted: true, size: 12),
            ],
          ),
        ),
        // ---- Reminders --------------------------------------------------------------
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Label('Daily reminders', bold: true),
                  _AppSwitch(
                    label: 'Daily reminders',
                    value: prefs.reminders,
                    enabled: ready && !_saving,
                    onChanged: _toggleReminders,
                  ),
                ],
              ),
              const Label(
                'A quiet nudge at your chosen time in each commitment’s time zone. Reminders stop '
                'when you pause, finish, or break an attempt.',
                size: 13,
                muted: true,
              ),
              AppField(
                label: 'Reminder time (24-hour)',
                value: _time,
                maxLength: 5,
                placeholder: '20:00',
                onChanged: (v) => _time = v,
              ),
              LockButton(
                light: true,
                title: 'SAVE REMINDER TIME',
                loading: _saving,
                disabled: !ready,
                onPressed: () => _save(() async {
                  await controller.update(reminderTime: _time);
                  if (mounted) setState(() => _message = 'Reminder time saved.');
                }),
              ),
              if (status.isNotEmpty) Label(status, size: 12, muted: true),
              LockButton(
                light: true,
                title: 'SEND TEST REMINDER',
                disabled: _saving || !prefs.reminders,
                onPressed: () => _save(() async {
                  await ref.read(notificationServiceProvider).sendTest();
                  if (mounted) setState(() => _message = 'Test reminder scheduled in 5 seconds.');
                }),
              ),
              LockButton(
                light: true,
                title: 'REFRESH REMINDERS',
                disabled: _saving,
                onPressed: () => ref.read(reminderRevisionProvider.notifier).bump(),
              ),
              LockButton(
                light: true,
                title: 'OPEN DEVICE SETTINGS',
                onPressed: () => unawaited(
                  AppSettings.openAppSettings(type: AppSettingsType.notification).catchError(
                    (Object _) {
                      if (mounted) setState(() => _error = 'Could not open device settings.');
                    },
                  ),
                ),
              ),
              const Label(
                'Reminders have no habit names or private notes on your lock screen. Check-ins update '
                'the schedule; your device may delay delivery.',
                size: 11,
                muted: true,
              ),
            ],
          ),
        ),
        if (_message.isNotEmpty) Semantics(liveRegion: true, child: Label(_message, size: 13)),
        if (_error.isNotEmpty) ErrorNote(_error),
        LockButton(
          light: true,
          title: device ? 'LEAVE LOCAL SESSION' : 'SIGN OUT',
          onPressed: () => unawaited(_confirmSignOut(device)),
        ),
        const Label('LockIn · ${AppConfig.appVersion}', size: 11, muted: true, align: TextAlign.center),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Label(label),
            _AppSwitch(label: label, value: value, enabled: enabled, onChanged: onChanged),
          ],
        ),
      );
}

class _AppSwitch extends StatelessWidget {
  const _AppSwitch({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeTrackColor: AppColors.successBackground,
          activeThumbColor: AppColors.successForeground,
        ),
      );
}

class _SignOutModal extends ConsumerStatefulWidget {
  const _SignOutModal({required this.device});

  final bool device;

  @override
  ConsumerState<_SignOutModal> createState() => _SignOutModalState();
}

class _SignOutModalState extends ConsumerState<_SignOutModal> {
  bool _busy = false;
  String _error = '';

  Future<void> _exit() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ref.read(sessionProvider.notifier).signOut();
      // The router moves to the sign-in screen by itself; close the dialog.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not sign out. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ModalCard(
        title: widget.device ? 'Leave this session?' : 'Sign out?',
        busy: _busy,
        children: [
          Label(
            widget.device
                ? 'Your local commitments will remain on this device. Choose Continue on this device to return.'
                : 'You will need to sign in again to see your commitments.',
          ),
          if (_error.isNotEmpty) ErrorNote(_error),
          LockButton(
            title: widget.device ? 'LEAVE SESSION' : 'SIGN OUT',
            loading: _busy,
            onPressed: () => unawaited(_exit()),
          ),
          LockButton(
            light: true,
            title: 'STAY HERE',
            disabled: _busy,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
}
