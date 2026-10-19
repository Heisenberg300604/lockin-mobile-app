// Tests for the reminder plan and scheduler, ported from the React Native
// suite (tests/reminders.test.ts).
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/features/commitments/domain/models.dart';
import 'package:lockin/features/reminders/data/reminder_scheduler.dart';
import 'package:lockin/features/reminders/domain/reminder_plan.dart';

import '../helpers.dart';

final now = DateTime.parse('2026-06-04T06:00:00Z');

Commitment kolkata({CommitmentStatus status = CommitmentStatus.active, Pace pace = const DailyPace(1)}) =>
    Commitment(
      id: 'one',
      attemptId: 'one',
      name: 'Private target',
      description: '',
      path: HabitPath.build,
      reward: 'Coffee',
      pace: pace,
      startDate: '2026-06-04',
      duration: 7,
      timeZone: 'Asia/Kolkata',
      status: status,
      createdAt: '2026-06-04T00:00:00Z',
    );

int ms(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

/// A fake operating system holding "pending notifications".
class FakeBackend implements ReminderBackend {
  final Map<String, String> pending = {'unrelated': 'other', 'old': 'lockin:old'};
  int scheduled = 0;
  bool failOnce = false;

  @override
  Future<List<({String id, String? key})>> list() async =>
      [for (final e in pending.entries) (id: e.key, key: e.value)];

  @override
  Future<void> cancel(String id) async => pending.remove(id);

  @override
  Future<void> schedule(Reminder r) async {
    if (failOnce && scheduled == 1) {
      failOnce = false;
      throw StateError('native error');
    }
    scheduled++;
    pending[r.key] = r.key;
  }
}

void main() {
  setUpAll(initTimeZones);
  final data = Snapshot(commitments: [kolkata()]);

  test('reminders use attempt timezone, stop at unresolved expiry, and deduplicate', () {
    final plan = reminderPlan(data, '20:00', now);
    expect(plan.length, 2);
    expect(plan[0].at, ms('2026-06-04T14:30:00Z'));
    expect(plan[1].at, ms('2026-06-05T14:30:00Z'));
    expect(plan[1].date, '2026-06-04');
  });

  test('saving progress cancels obsolete nudges and opens the next schedule', () {
    final done = data.copyWith(checkIns: [
      CheckIn(attemptId: 'one', date: '2026-06-04', count: 1, updatedAt: now.toIso8601String()),
    ]);
    final plan = reminderPlan(done, '20:00', now);
    expect(plan.any((r) => r.date == '2026-06-04'), isFalse);
    expect(plan.first.date, '2026-06-05');
  });

  test('paused and terminal attempts schedule nothing; rest dates are skipped', () {
    for (final status in [CommitmentStatus.paused, CommitmentStatus.broken, CommitmentStatus.completed]) {
      expect(reminderPlan(Snapshot(commitments: [kolkata(status: status)]), '20:00', now), isEmpty);
    }
    final plan = reminderPlan(
      Snapshot(commitments: [kolkata(pace: const CustomPace([0]))]),
      '20:00',
      now,
    );
    expect(plan.first.date, '2026-06-08');
  });

  test('weekly reminders skip successful dates and stop after quota is met', () {
    final plan = reminderPlan(
      Snapshot(
        commitments: [kolkata(pace: const WeeklyPace(1))],
        checkIns: [
          CheckIn(attemptId: 'one', date: '2026-06-04', count: 1, updatedAt: now.toIso8601String()),
        ],
      ),
      '20:00',
      now,
    );
    expect(plan, isEmpty);
  });

  test('wall-clock reminder time survives DST and nonexistent time is skipped', () {
    expect(reminderInstant('2026-03-08', '20:00', 'America/New_York'), ms('2026-03-09T00:00:00Z'));
    expect(reminderInstant('2026-11-01', '20:00', 'America/New_York'), ms('2026-11-02T01:00:00Z'));
    expect(reminderInstant('2026-03-08', '02:30', 'America/New_York'), isNull);
  });

  test('scheduler retains matching requests, cancels stale ones, clears only its own', () async {
    final backend = FakeBackend();
    final sync = ReminderScheduler(backend);
    final plan = reminderPlan(data, '20:00', now);
    await Future.wait([sync.sync(plan), sync.sync(plan)]);
    expect(backend.scheduled, plan.length);
    expect(backend.pending.containsKey('old'), isFalse);
    await sync.sync([]);
    expect(backend.pending, {'unrelated': 'other'});
  });

  test('scheduler recovers after partial scheduling failure without duplicates', () async {
    final backend = FakeBackend()
      ..pending.clear()
      ..failOnce = true;
    final sync = ReminderScheduler(backend);
    final plan = reminderPlan(data, '20:00', now);
    // The first request succeeds, the second throws (a "native error").
    await expectLater(sync.sync(plan), throwsA(isA<StateError>()));
    await sync.sync(plan);
    expect(backend.pending.length, plan.length);
  });
}
