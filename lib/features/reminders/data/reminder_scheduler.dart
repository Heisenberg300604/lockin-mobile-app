/// Makes the phone's scheduled notifications match a reminder plan.
///
/// The *plan* (what should exist) comes from `reminder_plan.dart`. The
/// *backend* (how to talk to the operating system) is hidden behind
/// [ReminderBackend], so this class can be tested without a phone.
///
/// The strategy is "diff, don't rebuild":
/// * keep notifications that are already scheduled and still wanted,
/// * cancel the ones that are no longer wanted (only ours, keyed `lockin:`),
/// * schedule the missing ones.
///
/// If something fails half-way (say the OS rejects one request), the next run
/// simply repeats the diff and finishes the job without creating duplicates.
library;

import '../domain/reminder_plan.dart';

/// How the scheduler talks to the operating system.
abstract interface class ReminderBackend {
  /// All currently scheduled notifications. [key] is our [Reminder.key] if the
  /// notification is one of ours.
  Future<List<({String id, String? key})>> list();

  /// Cancels the notification with [id].
  Future<void> cancel(String id);

  /// Schedules [reminder].
  Future<void> schedule(Reminder reminder);
}

/// Serialised, idempotent synchroniser between a plan and the OS.
class ReminderScheduler {
  /// Creates a scheduler on top of [backend].
  ReminderScheduler(this._backend);

  final ReminderBackend _backend;
  Future<void> _queue = Future<void>.value();

  /// Brings the OS in line with [plan]. Calls are queued, so two overlapping
  /// syncs never run at the same time.
  Future<void> sync(List<Reminder> plan) {
    final task = _queue.then((_) async {
      final existing = await _backend.list();
      final wanted = {for (final r in plan) r.key: r};
      final retained = <String>{};
      for (final item in existing) {
        final key = item.key;
        if (key == null || !key.startsWith('lockin:')) continue; // not ours
        if (!wanted.containsKey(key) || retained.contains(key)) {
          await _backend.cancel(item.id);
        } else {
          retained.add(key);
        }
      }
      for (final r in plan) {
        if (!retained.contains(r.key)) await _backend.schedule(r);
      }
    });
    _queue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }
}
