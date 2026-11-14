// The API/web-app rules: two-day backfill, calendar states, period status,
// creation feasibility and "Today's Tracking" rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/core/utils/calendar_date.dart';
import 'package:lockin/features/commitments/domain/api_progress.dart';
import 'package:lockin/features/commitments/domain/models.dart';

import '../helpers.dart';

CheckIn kept(String date, {String? createdAt, String id = 'old'}) => CheckIn(
  attemptId: id,
  date: date,
  count: 1,
  outcome: CheckInOutcome.success,
  updatedAt: createdAt ?? '${date}T09:00:00Z',
  createdAt: createdAt ?? '${date}T09:00:00Z',
);

void main() {
  setUpAll(initTimeZones);

  // 7-day daily commitment, Thu 2026-06-04 .. Wed 2026-06-10, UTC.
  final daily = baseCommitment();

  group('backfill window', () {
    test(
      'today and the previous two days are loggable, older days are not',
      () {
        final now = at('2026-06-08');
        expect(canApiCheckIn(daily, const [], '2026-06-08', now), isTrue);
        expect(canApiCheckIn(daily, const [], '2026-06-07', now), isTrue);
        expect(canApiCheckIn(daily, const [], '2026-06-06', now), isTrue);
        expect(canApiCheckIn(daily, const [], '2026-06-05', now), isFalse);
        expect(
          apiCalendarState(daily, const [], '2026-06-05', '2026-06-08'),
          CalendarDayState.expired,
        );
      },
    );

    test(
      'future, already-logged, outside and inactive days are not loggable',
      () {
        final now = at('2026-06-08');
        expect(canApiCheckIn(daily, const [], '2026-06-09', now), isFalse);
        expect(
          canApiCheckIn(daily, [kept('2026-06-07')], '2026-06-07', now),
          isFalse,
        );
        expect(
          canApiCheckIn(daily, const [], '2026-06-03', at('2026-06-04')),
          isFalse,
        );
        final paused = baseCommitment(status: CommitmentStatus.paused);
        expect(canApiCheckIn(paused, const [], '2026-06-08', now), isFalse);
      },
    );

    test('fixed schedules only accept their weekdays', () {
      // Monday only (0). 2026-06-08 is a Monday, 2026-06-09 a Tuesday.
      final mondays = baseCommitment(pace: const CustomPace([0]), duration: 14);
      expect(
        canApiCheckIn(mondays, const [], '2026-06-08', at('2026-06-09')),
        isTrue,
      );
      expect(
        apiCalendarState(mondays, const [], '2026-06-09', '2026-06-09'),
        CalendarDayState.notScheduled,
      );
    });
  });

  test('legacy browser zone names such as Asia/Calcutta resolve', () {
    expect(
      dateInZone(DateTime.parse('2026-06-04T20:00:00Z'), 'Asia/Calcutta'),
      '2026-06-05',
    );
    // Unknown names fall back instead of throwing.
    expect(
      dateInZone(DateTime.parse('2026-06-04T20:00:00Z'), 'Mars/Olympus'),
      '2026-06-04',
    );
  });

  test('a check-in created on a later day is shown as logged late', () {
    final checkIns = [
      kept('2026-06-05'),
      kept('2026-06-06', createdAt: '2026-06-07T10:00:00Z'),
    ];
    expect(
      apiCalendarState(daily, checkIns, '2026-06-05', '2026-06-07'),
      CalendarDayState.keptOnTime,
    );
    expect(
      apiCalendarState(daily, checkIns, '2026-06-06', '2026-06-07'),
      CalendarDayState.keptLate,
    );
  });

  test('weekly period status: secured, on track, at risk', () {
    // 3 per Monday-Sunday week, starting Monday 2026-06-08 for 14 days.
    const weekly = Commitment(
      id: 'w',
      attemptId: 'w',
      path: HabitPath.build,
      name: 'Run',
      description: '',
      startDate: '2026-06-08',
      duration: 14,
      pace: WeeklyPace(3),
      reward: 'Coffee',
      timeZone: 'UTC',
      status: CommitmentStatus.active,
      createdAt: '2026-06-08T00:00:00Z',
    );
    final three = [
      for (final d in ['08', '09', '10']) kept('2026-06-$d', id: 'w'),
    ];
    expect(
      apiProgress(weekly, three, at('2026-06-11')).periodState,
      PeriodState.secured,
    );
    expect(
      apiProgress(weekly, const [], at('2026-06-12')).periodState,
      PeriodState.onTrack,
    );
    // Saturday with nothing logged: only Sat + Sun remain for a target of 3.
    final risk = apiProgress(weekly, const [], at('2026-06-13'));
    expect(risk.periodState, PeriodState.atRisk);
    expect(risk.periodMessage, contains('at risk'));
  });

  group('feasibility (mirrors the server)', () {
    test('a partial first week must still allow the weekly target', () {
      // Saturday start: the first week has only Sat + Sun.
      expect(
        apiFeasibilityError(
          startDate: '2026-06-13',
          duration: 30,
          pace: const WeeklyPace(3),
        ),
        isNotNull,
      );
      expect(
        apiFeasibilityError(
          startDate: '2026-06-08',
          duration: 28,
          pace: const WeeklyPace(3),
        ),
        isNull,
      );
    });

    test('fixed schedules need every chosen weekday in each partial week', () {
      // Mon/Wed/Fri starting on a Wednesday misses Monday in week one.
      expect(
        apiFeasibilityError(
          startDate: '2026-06-10',
          duration: 28,
          pace: const CustomPace([0, 2, 4]),
        ),
        isNotNull,
      );
      expect(
        apiFeasibilityError(
          startDate: '2026-06-10',
          duration: 30,
          pace: const DailyPace(1),
        ),
        isNull,
      );
    });

    test('monthly targets are checked per calendar month', () {
      expect(
        apiFeasibilityError(
          startDate: '2026-06-20',
          duration: 30,
          pace: const MonthlyPace(15),
        ),
        isNotNull,
      );
      expect(
        apiFeasibilityError(
          startDate: '2026-06-01',
          duration: 30,
          pace: const MonthlyPace(15),
        ),
        isNull,
      );
    });
  });

  test(
    "tracking rows: today first, then unlogged backfill days for daily habits",
    () {
      final snapshot = Snapshot(
        commitments: [daily],
        checkIns: [kept('2026-06-06')],
      );
      final rows = apiDueRows(snapshot, at('2026-06-08'));
      expect(rows.map((r) => (r.date, r.catchUp)).toList(), [
        ('2026-06-08', false),
        ('2026-06-07', true),
      ]);
    },
  );
}
