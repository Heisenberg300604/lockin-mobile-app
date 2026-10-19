// Tests for the scheduling rules (schedule.dart, validation.dart) and the
// local repository's basic behaviour. Ported from the React Native test-suite
// (tests/commitments.test.ts) so the Flutter app is proven to behave the same.
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/utils/calendar_date.dart';
import 'package:lockin/features/commitments/data/key_value_store.dart';
import 'package:lockin/features/commitments/data/local_commitment_repository.dart';
import 'package:lockin/features/commitments/domain/models.dart';
import 'package:lockin/features/commitments/domain/schedule.dart';
import 'package:lockin/features/commitments/domain/validation.dart';

import '../helpers.dart';

final now = DateTime.parse('2026-06-05T06:30:00Z');

Commitment kolkata() => const Commitment(
  id: 'c1',
  attemptId: 'a1',
  path: HabitPath.build,
  name: 'Yoga',
  description: '',
  startDate: '2026-06-04',
  duration: 7,
  pace: DailyPace(1),
  reward: 'Coffee',
  timeZone: 'Asia/Kolkata',
  status: CommitmentStatus.active,
  createdAt: '2026-06-04T01:00:00Z',
);

Draft validDraft() => freshDraft(now).copyWith(
  path: HabitPath.build,
  name: 'Yoga',
  startDate: '2026-06-05',
  reward: 'Coffee',
);

void main() {
  setUpAll(initTimeZones);
  setUp(() => DeviceZone.current = 'Asia/Kolkata');

  test('inclusive durations cross month boundaries correctly', () {
    final c = Commitment.fromJson({...kolkata().toJson(), 'duration': 45});
    expect(endDate(c), '2026-07-18');
    expect(addDays('2026-12-31', 1), '2027-01-01');
  });

  test('logical dates follow the attempt zone rather than UTC', () {
    expect(
      dateInZone(DateTime.parse('2026-06-04T20:00:00Z'), 'Asia/Kolkata'),
      '2026-06-05',
    );
  });

  test('catch-up belongs to yesterday and ends at an exact boundary', () {
    final c = kolkata();
    expect(
      deadline(c, '2026-06-04'),
      DateTime.parse('2026-06-05T18:30:00Z').millisecondsSinceEpoch,
    );
    expect(canLog(c, '2026-06-04', now), isTrue);
    expect(
      canLog(c, '2026-06-04', DateTime.parse('2026-06-05T18:30:00Z')),
      isFalse,
    );
  });

  test('grace remains 24 elapsed hours across daylight saving', () {
    final c = Commitment.fromJson({
      ...kolkata().toJson(),
      'timeZone': 'America/New_York',
      'startDate': '2026-03-07',
    });
    expect(
      deadline(c, '2026-03-07'),
      DateTime.parse('2026-03-09T05:00:00Z').millisecondsSinceEpoch,
    );
  });

  test('future, rest, and terminal dates cannot be logged', () {
    final c = kolkata();
    expect(canLog(c, '2026-06-06', now), isFalse);
    final custom = Commitment.fromJson({
      ...c.toJson(),
      'pace': const CustomPace([0, 2]).toJson(),
    });
    expect(canLog(custom, '2026-06-05', now), isFalse);
    final broken = Commitment.fromJson({...c.toJson(), 'status': 'broken'});
    expect(canLog(broken, '2026-06-05', now), isFalse);
  });

  test(
    'partial weekly periods round up and count distinct successful dates',
    () {
      final c = Commitment.fromJson({
        ...kolkata().toJson(),
        'duration': 10,
        'pace': const WeeklyPace(3).toJson(),
      });
      final period = weeklyPeriod(c, '2026-06-12');
      expect(period.start, '2026-06-11');
      expect(period.end, '2026-06-13');
      expect(period.required, 2);

      final entries = [
        for (final d in ['2026-06-11', '2026-06-11', '2026-06-12'])
          CheckIn(
            attemptId: 'a1',
            date: d,
            count: 1,
            updatedAt: now.toIso8601String(),
          ),
      ];
      final p = progress(c, entries, '2026-06-12');
      expect((p.count, p.target, p.done), (2, 2, true));
    },
  );

  test(
    'today plus unfinished catch-up appear without already-complete yesterday',
    () {
      final rows = dueRows(
        Snapshot(
          commitments: [kolkata()],
          checkIns: [
            CheckIn(
              attemptId: 'a1',
              date: '2026-06-04',
              count: 1,
              updatedAt: now.toIso8601String(),
            ),
          ],
        ),
        now,
      );
      expect(rows.map((r) => r.date).toList(), ['2026-06-05']);
    },
  );

  test(
    'a custom schedule must contain an actual due date within the duration',
    () {
      final draft = validDraft().copyWith(
        duration: 1,
        pace: const CustomPace([0]),
      );
      expect(validateDraft(draft, now), contains('occur'));
    },
  );

  test('invalid dates, counts and oversized inputs fail before storage', () {
    expect(
      validateDraft(validDraft().copyWith(startDate: '2026-02-30'), now),
      contains('start date'),
    );
    expect(
      validateDraft(validDraft().copyWith(pace: const WeeklyPace(8)), now),
      contains('target'),
    );
    expect(
      validateDraft(validDraft().copyWith(name: 'x' * 81), now),
      contains('80'),
    );
  });

  test(
    'a restored draft with a past start date moves to today instead of failing',
    () {
      final stale = validDraft().copyWith(startDate: '2026-06-01');
      expect(validateDraft(stale, now), isNotNull);
      final fixed = withCurrentStart(stale, now);
      expect(fixed.startDate, '2026-06-05');
      expect(fixed.duration, stale.duration);
      expect(validateDraft(fixed, now), isNull);
      // A future start date is left alone.
      final future = validDraft().copyWith(startDate: '2026-07-01');
      expect(withCurrentStart(future, now).startDate, '2026-07-01');
    },
  );

  group('local repository', () {
    LocalCommitmentRepository repo(MemoryStore store) =>
        LocalCommitmentRepository(
          store: store,
          storageKey: 'k',
          clock: () => now,
        );

    test(
      'lock retries are idempotent and a new repository reloads saved data',
      () async {
        final store = MemoryStore();
        final r = repo(store);
        final results = await Future.wait([
          r.create(validDraft(), 'request-1'),
          r.create(validDraft(), 'request-1'),
        ]);
        expect(results[0].id, results[1].id);
        expect((await repo(store).load()).commitments.length, 1);
      },
    );

    test(
      'concurrent check-ins serialize and an absolute count gives no extra credit',
      () async {
        final r = repo(MemoryStore());
        final c = await r.create(
          validDraft().copyWith(pace: const DailyPace(10)),
          'request-2',
        );
        await Future.wait([
          r.log(c, '2026-06-05', 3),
          r.log(c, '2026-06-05', 3),
        ]);
        final snapshot = await r.load();
        expect(snapshot.checkIns.length, 1);
        expect(snapshot.checkIns.first.count, 3);
      },
    );

    test(
      'failed persistence rejects rather than claiming a successful lock',
      () async {
        final store = FlakyStore()..failWrites = true;
        await expectLater(
          repo(store).create(validDraft(), 'request-3'),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('a failed queued write does not poison subsequent writes', () async {
      final r = repo(MemoryStore());
      await expectLater(
        r.create(validDraft().copyWith(name: ''), 'bad'),
        throwsA(anything),
      );
      await r.create(validDraft(), 'good');
      expect((await r.load()).commitments.length, 1);
    });

    test(
      'out-of-window and excessive counts leave saved logs unchanged',
      () async {
        final r = repo(MemoryStore());
        final c = await r.create(validDraft(), 'request-4');
        await expectLater(
          r.log(c, '2026-06-05', 2),
          throwsA(isA<LockInException>()),
        );
        await expectLater(
          r.log(c, '2026-06-06', 1),
          throwsA(isA<LockInException>()),
        );
        expect((await r.load()).checkIns, isEmpty);
      },
    );
  });
}
