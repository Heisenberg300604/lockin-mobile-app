/// Riverpod wiring for reminders.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../commitments/application/commitments_controller.dart';
import '../../settings/application/preferences_controller.dart';
import '../data/notification_service.dart';
import '../data/reminder_scheduler.dart';
import '../domain/reminder_plan.dart';

/// The one [NotificationService]. Overridden in tests with a fake.
final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// The synchroniser between plans and the OS.
final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => ReminderScheduler(ref.watch(notificationServiceProvider)),
);

/// A short sentence describing the reminder state, shown in Settings.
class ReminderStatus extends Notifier<String> {
  @override
  String build() => '';

  /// Replaces the status text.
  void set(String value) => state = value;
}

/// Status line for the reminders card.
final reminderStatusProvider = NotifierProvider<ReminderStatus, String>(ReminderStatus.new);

/// Bumped by the "Refresh reminders" button to force a re-sync.
class ReminderRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Requests a re-sync.
  void bump() => state++;
}

/// Manual re-sync counter.
final reminderRevisionProvider = NotifierProvider<ReminderRevision, int>(ReminderRevision.new);

/// An "effect" provider: it produces no value, it just keeps the phone's
/// scheduled notifications in line with the data and preferences.
///
/// It is re-run automatically whenever the commitments, the clock tick, the
/// preferences or the manual revision change (that is what `ref.watch` means),
/// and is kept alive by being watched in `app.dart`.
final reminderSyncProvider = Provider<void>((ref) {
  final prefsState = ref.watch(preferencesProvider);
  final data = ref.watch(commitmentsProvider);
  ref.watch(reminderRevisionProvider);
  if (!prefsState.ready || data.loading) return;

  final prefs = prefsState.preferences;
  final status = ref.read(reminderStatusProvider.notifier);
  final service = ref.read(notificationServiceProvider);
  final scheduler = ref.read(reminderSchedulerProvider);

  unawaited(() async {
    try {
      final allowed = await service.permission();
      final plan = prefs.reminders && allowed
          ? reminderPlan(data.snapshot, prefs.reminderTime, data.now)
          : <Reminder>[];
      await scheduler.sync(plan);
      if (!ref.mounted) return;
      status.set(
        !prefs.reminders
            ? 'Reminders are off.'
            : !allowed
                ? 'Notifications are blocked. Allow them in device settings.'
                : plan.isNotEmpty
                    ? '${plan.length} upcoming reminders scheduled.'
                    : "No reminders are due. They'll update when you check in or resume.",
      );
    } catch (_) {
      if (ref.mounted) {
        status.set('Reminders could not be updated. Retry to sync your schedule.');
      }
    }
  }());
});

/// Cancels every LockIn reminder on the phone (used on sign-out).
Future<void> clearReminders(Ref ref) async {
  try {
    await ref.read(notificationServiceProvider).clearAll();
  } catch (_) {
    // Nothing to clear, or the plugin is unavailable: not worth failing for.
  }
}
