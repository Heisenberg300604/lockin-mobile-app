// Tests for pause / resume / expiry / restart / completion (lifecycle.dart),
// ported from the React Native suite (tests/lifecycle.test.ts).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/features/commitments/data/local_commitment_repository.dart';
import 'package:lockin/features/commitments/domain/lifecycle.dart';
import 'package:lockin/features/commitments/domain/models.dart';
import 'package:lockin/features/commitments/domain/schedule.dart';

import '../helpers.dart';

/// A test rig: a repository over a controllable clock and a snapshot we can
/// inspect directly in storage.
class Harness {
  Harness(Snapshot data) {
    store.setString(key, jsonEncode(data.toJson()));
    repo = LocalCommitmentRepository(store: store, storageKey: key, clock: () => now);
  }

  final key = 'k';
  final FlakyStore store = FlakyStore();
  DateTime now = at('2026-06-04');
  late final LocalCommitmentRepository repo;

  /// What is currently stored on "disk".
  Snapshot saved() =>
      Snapshot.fromJson(jsonDecode(store.peek(key)!) as Map<String, dynamic>);
}

void main() {
  setUpAll(initTimeZones);
  final base = baseCommitment();

  test('pause preserves today, freezes dates, extends deadline, and preserves log dates', () {
    var c = pauseCommitment(base, at('2026-06-06'));
    expect(canLog(c, '2026-06-06', at('2026-06-06')), isTrue);
    expect(canLog(c, '2026-06-07', at('2026-06-07')), isFalse);
    expect(dayOrdinal(c, '2026-06-08'), 3);
    c = resumeCommitment(c, at('2026-06-09'));
    expect(endDate(c), '2026-06-12');
    expect(dayOrdinal(c, '2026-06-09'), 4);
    expect(activeDates(c), [
      '2026-06-04', '2026-06-05', '2026-06-06', '2026-06-09',
      '2026-06-10', '2026-06-11', '2026-06-12',
    ]);
  });

  test('same-day pause/resume adds zero days, repeated pauses add only frozen dates', () {
    var c = pauseCommitment(base, at('2026-06-04'));
    c = resumeCommitment(c, at('2026-06-04'));
    expect(endDate(c), '2026-06-10');
    c = pauseCommitment(c, at('2026-06-04'));
    c = resumeCommitment(c, at('2026-06-07'));
    c = pauseCommitment(c, at('2026-06-08'));
    c = resumeCommitment(c, at('2026-06-10'));
    expect(endDate(c), '2026-06-13');
    expect(activeDates(c).length, 7);
  });

  test('future and final-date attempts cannot pause', () {
    expect(() => pauseCommitment(base, at('2026-06-03')), throwsA(isA<LockInException>()));
    expect(() => pauseCommitment(base, at('2026-06-10')), throwsA(isA<LockInException>()));
  });

  test('automatic expiry respects exact grace and remains idempotent', () {
    final data = snapshotWith(base);
    final early = reconcile(data, DateTime.parse('2026-06-05T23:59:59Z'));
    expect(identical(early, data), isTrue);
    final expired = reconcile(data, DateTime.parse('2026-06-06T00:00:00Z'));
    expect(identical(expired, data), isFalse);
    expect(expired.commitments.first.failureDate, '2026-06-04');
    expect(expired.commitments.first.events.length, 1);
    expect(identical(reconcile(expired, at('2026-06-12')), expired), isTrue);
  });

  test('pause cannot erase old obligations; expired resume rejects and persists broken', () async {
    final h = Harness(snapshotWith(base));
    await h.repo.pause(base);
    h.now = at('2026-06-06');
    await expectLater(h.repo.resume(base), throwsA(isA<LockInException>()));
    final c = h.saved().commitments.first;
    expect(c.status, CommitmentStatus.broken);
    expect(c.failureDate, '2026-06-04');
  });

  test('explicit daily failure is immediate; restart atomically preserves notes and old logs', () async {
    final h = Harness(snapshotWith(base));
    await h.repo.log(base, '2026-06-04', 1);
    await h.repo.fail(base, '2026-06-04');
    expect(h.saved().commitments.first.status, CommitmentStatus.broken);

    final results = await Future.wait([
      h.repo.restart(base, 'new-a', 'Low Energy', ''),
      h.repo.restart(base, 'new-b', 'Low Energy', ''),
    ]);
    expect(results[0].attemptId, results[1].attemptId);
    expect(results[0].previousAttemptId, 'old');
    expect(results[0].timeZone, 'UTC');
    expect(results[0].status, CommitmentStatus.active);

    final data = await h.repo.load();
    expect(data.commitments.length, 2);
    expect(data.commitments.firstWhere((c) => c.id == 'old').reflection?.reason, 'Low Energy');
    expect(data.checkIns.first.outcome, CheckInOutcome.missed);
    expect(data.checkIns.first.attemptId, 'old');
  });

  test('failed restart persistence leaves reflection and replacement absent', () async {
    final h = Harness(snapshotWith(baseCommitment(status: CommitmentStatus.broken)));
    h.store.failWrites = true;
    await expectLater(
      h.repo.restart(base, 'new', '', 'Private note'),
      throwsA(isA<StateError>()),
    );
    expect(h.saved().commitments.length, 1);
    expect(h.saved().commitments.first.reflection, isNull);
  });

  test('weekly missed date stays active; quota fails only after period catch-up', () async {
    final c = baseCommitment(pace: const WeeklyPace(3));
    final h = Harness(snapshotWith(c));
    await h.repo.fail(c, '2026-06-04');
    expect(h.saved().commitments.first.status, CommitmentStatus.active);
    h.now = DateTime.parse('2026-06-11T23:59:59Z');
    expect((await h.repo.load()).commitments.first.status, CommitmentStatus.active);
    h.now = DateTime.parse('2026-06-12T00:00:00Z');
    expect((await h.repo.load()).commitments.first.failureReason, FailureReason.quota);
  });

  test('weekly period freezes while paused and resumes its remaining active dates', () {
    final c = pauseCommitment(baseCommitment(pace: const WeeklyPace(3)), at('2026-06-06'));
    var data = snapshotWith(c, ['2026-06-04']);
    data = reconcile(data, at('2026-06-20'));
    expect(data.commitments.first.status, CommitmentStatus.paused);

    final resumed = resumeCommitment(data.commitments.first, at('2026-06-21'));
    data = data.copyWith(commitments: [resumed]);
    expect(endDate(resumed), '2026-06-24');
    expect(progress(resumed, data.checkIns, '2026-06-22').target, 3);

    data = reconcile(data, DateTime.parse('2026-06-26T00:00:00Z'));
    expect(data.commitments.first.failureDate, '2026-06-24');
  });

  test('completion waits for final midnight; catch-up success unlocks reward', () async {
    final c = baseCommitment(duration: 1);
    final h = Harness(snapshotWith(c));
    await h.repo.log(c, '2026-06-04', 1);
    expect(h.saved().commitments.first.status, CommitmentStatus.active);
    h.now = DateTime.parse('2026-06-05T00:00:00Z');
    expect((await h.repo.load()).commitments.first.status, CommitmentStatus.completed);

    final late = Harness(snapshotWith(c));
    late.now = at('2026-06-05');
    expect((await late.repo.load()).commitments.first.status, CommitmentStatus.active);
    await late.repo.log(c, '2026-06-04', 1);
    expect(late.saved().commitments.first.status, CommitmentStatus.completed);
  });

  test('partial count expires and terminal attempts reject further writes', () async {
    final c = baseCommitment(pace: const DailyPace(10));
    final h = Harness(snapshotWith(c));
    await h.repo.log(c, '2026-06-04', 3);
    h.now = at('2026-06-06');
    await expectLater(h.repo.log(c, '2026-06-06', 10), throwsA(isA<LockInException>()));
    expect(h.saved().commitments.first.status, CommitmentStatus.broken);
    expect(h.saved().checkIns.first.count, 3);
  });

  test('rest dates cannot fail and do not interrupt a custom schedule streak', () {
    final c = baseCommitment(pace: const CustomPace([3, 5]));
    var data = snapshotWith(c, ['2026-06-04', '2026-06-06']);
    data = reconcile(data, at('2026-06-07'));
    expect(data.commitments.first.status, CommitmentStatus.active);
    expect(streak(c, data.checkIns, at('2026-06-07')).count, 2);
  });

  test('short weekly final quota must succeed before completion', () {
    final c = baseCommitment(duration: 3, pace: const WeeklyPace(3));
    var data = snapshotWith(c, ['2026-06-04']);
    data = reconcile(data, at('2026-06-07'));
    expect(data.commitments.first.status, CommitmentStatus.active);
    data = data.copyWith(checkIns: [
      ...data.checkIns,
      CheckIn(
        attemptId: c.attemptId,
        date: '2026-06-06',
        count: 1,
        updatedAt: at('2026-06-07').toIso8601String(),
      ),
    ]);
    data = reconcile(data, at('2026-06-07'));
    expect(data.commitments.first.status, CommitmentStatus.completed);
  });
}
