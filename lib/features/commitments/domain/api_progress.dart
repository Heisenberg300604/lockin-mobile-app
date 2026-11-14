/// Rules that match the deployed LockIn API (and the LockIn web app).
///
/// The server is the source of truth: it decides which check-ins it accepts
/// and when a commitment breaks or completes. Everything here mirrors those
/// rules so the app never offers an action the server will reject:
///
/// * Rule periods are calendar based: a day, a Monday-to-Sunday week, a
///   calendar month, or a fixed window counted from the start date. Periods
///   at the edges of the timeline are clipped but keep the full target.
/// * A kept day may be logged for today or **backfilled for the previous two
///   days** ([apiBackfillDays]), inside the timeline, on a scheduled weekday,
///   while the commitment is active, and only once per date.
///
/// All dates are `yyyy-MM-dd` strings in the commitment's time zone.
library;

import '../../../core/utils/calendar_date.dart';
import 'models.dart';

/// How many days back a kept day may still be logged (server:
/// `DAILY_BACKFILL_DAYS`).
const int apiBackfillDays = 2;

/// Whether the current rule period is already met, still reachable, or can no
/// longer be met with the remaining days.
enum PeriodState { secured, onTrack, atRisk }

/// Progress for one rule period and for the whole timeline.
class ApiProgress {
  const ApiProgress({
    required this.durationDays,
    required this.elapsedDays,
    required this.daysRemaining,
    required this.elapsedPercent,
    required this.successfulCheckIns,
    required this.periodStart,
    required this.periodEnd,
    required this.periodProgress,
    required this.periodTarget,
    required this.periodLabel,
    required this.periodState,
    required this.checkedOnDate,
    required this.eligibleOnDate,
  });

  final int durationDays;
  final int elapsedDays;
  final int daysRemaining;
  final int elapsedPercent;
  final int successfulCheckIns;

  /// First and last day of the rule period containing the reference date.
  final String periodStart;
  final String periodEnd;

  /// Kept days inside the period, and how many are required.
  final int periodProgress;
  final int periodTarget;

  /// "Today", "This week", "This month" or "N-day window".
  final String periodLabel;
  final PeriodState periodState;

  /// Whether anything (kept or broken) is logged for the reference date.
  final bool checkedOnDate;

  /// Whether the reference date is a day check-ins can apply to at all
  /// (active, inside the timeline, scheduled). Ignores whether it is logged.
  final bool eligibleOnDate;

  /// True when the period target is met.
  bool get periodSecured => periodState == PeriodState.secured;

  /// Backwards-compatible names for "today" callers.
  bool get checkedToday => checkedOnDate;
  bool get eligibleToday => eligibleOnDate;

  /// One sentence describing the current period, as on the web app.
  String get periodMessage => switch (periodState) {
    PeriodState.secured =>
      '$periodLabel secured — $periodProgress of $periodTarget completed. '
          'Extra check-ins are optional.',
    PeriodState.atRisk =>
      '$periodLabel: $periodProgress of $periodTarget completed. '
          'This period is at risk.',
    PeriodState.onTrack =>
      '$periodLabel: $periodProgress of $periodTarget completed.',
  };
}

/// Last day of the commitment's timeline.
String apiEndDate(Commitment c) => addDays(c.startDate, c.duration - 1);

/// ISO weekdays (Monday = 1 ... Sunday = 7) a fixed weekly schedule requires,
/// or an empty set when every day counts.
Set<int> _scheduledIsoDays(Pace pace) => pace is CustomPace
    ? pace.days.map((day) => day + 1).toSet()
    : const <int>{};

bool _onSchedule(Pace pace, String date) {
  final days = _scheduledIsoDays(pace);
  return days.isEmpty || days.contains(dayOfWeek(date) + 1);
}

/// The check-in recorded for [date], if any.
CheckIn? apiCheckInOn(List<CheckIn> checkIns, Commitment c, String date) {
  for (final entry in checkIns) {
    if (entry.attemptId == c.attemptId && entry.date == date) return entry;
  }
  return null;
}

/// Calculates progress for the rule period containing [onDate] (defaults to
/// today in the commitment's zone, derived from [now]).
ApiProgress apiProgress(
  Commitment c,
  List<CheckIn> checkIns,
  DateTime now, {
  String? onDate,
}) {
  final date = onDate ?? dateInZone(now, c.timeZone);
  final end = apiEndDate(c);
  final duration = c.duration;
  final elapsed = date.compareTo(c.startDate) < 0
      ? 0
      : (dayDifference(c.startDate, date) + 1).clamp(0, duration);
  final reference = date.compareTo(c.startDate) < 0
      ? c.startDate
      : (date.compareTo(end) > 0 ? end : date);
  final period = _periodFor(c, reference);

  final own = checkIns.where((entry) => entry.attemptId == c.attemptId);
  final kept = own
      .where((entry) => entry.outcome == CheckInOutcome.success)
      .toList();
  final inPeriod = kept
      .where(
        (entry) =>
            entry.date.compareTo(period.start) >= 0 &&
            entry.date.compareTo(period.end) <= 0,
      )
      .length;
  final logged = own.map((entry) => entry.date).toSet();

  // Days still able to add progress to this period: from the reference date
  // (or the period start) to the period end, scheduled and not yet logged.
  var remaining = 0;
  for (
    var day = date.compareTo(period.start) > 0 ? date : period.start;
    day.compareTo(period.end) <= 0 && day.compareTo(end) <= 0;
    day = addDays(day, 1)
  ) {
    if (_onSchedule(c.pace, day) && !logged.contains(day)) remaining++;
  }
  final state = inPeriod >= period.target
      ? PeriodState.secured
      : inPeriod + remaining < period.target
      ? PeriodState.atRisk
      : PeriodState.onTrack;

  return ApiProgress(
    durationDays: duration,
    elapsedDays: elapsed,
    daysRemaining: duration - elapsed,
    elapsedPercent: ((elapsed / duration) * 100).round(),
    successfulCheckIns: kept.length,
    periodStart: period.start,
    periodEnd: period.end,
    periodProgress: inPeriod,
    periodTarget: period.target,
    periodLabel: period.label,
    periodState: state,
    checkedOnDate: logged.contains(date),
    eligibleOnDate:
        c.status == CommitmentStatus.active &&
        date.compareTo(c.startDate) >= 0 &&
        date.compareTo(end) <= 0 &&
        _onSchedule(c.pace, date),
  );
}

({String start, String end, int target, String label}) _periodFor(
  Commitment c,
  String date,
) {
  final pace = c.pace;
  if (pace is WeeklyPace || pace is CustomPace) {
    final monday = addDays(date, -dayOfWeek(date));
    return (
      start: monday,
      end: addDays(monday, 6),
      target: pace is WeeklyPace
          ? pace.count
          : (pace as CustomPace).days.length,
      label: 'This week',
    );
  }
  if (pace is MonthlyPace) {
    final start = '${date.substring(0, 7)}-01';
    return (
      start: start,
      end: _monthEnd(date),
      target: pace.count,
      label: 'This month',
    );
  }
  if (pace is WindowPace) {
    final offset = dayDifference(c.startDate, date);
    final block = (offset < 0 ? 0 : offset) ~/ pace.windowDays;
    final start = addDays(c.startDate, block * pace.windowDays);
    return (
      start: start,
      end: addDays(start, pace.windowDays - 1),
      target: pace.targetCount,
      label: '${pace.windowDays}-day window',
    );
  }
  return (start: date, end: date, target: 1, label: 'Today');
}

String _monthEnd(String date) {
  final parsed = DateTime.parse('${date.substring(0, 7)}-01T12:00:00Z');
  final nextMonth = DateTime.utc(parsed.year, parsed.month + 1, 1, 12);
  return addDays(
    '${nextMonth.year.toString().padLeft(4, '0')}-'
    '${nextMonth.month.toString().padLeft(2, '0')}-01',
    -1,
  );
}

// ---------------------------------------------------------------------------
// Check-in calendar
// ---------------------------------------------------------------------------

/// What a day in the check-in calendar represents (mirrors the web app).
enum CalendarDayState {
  /// Logged as kept on the day itself.
  keptOnTime,

  /// Logged as kept on a later day (backfilled).
  keptLate,

  /// A quit commitment was broken on this day.
  broken,

  /// Before the start or after the end of the timeline.
  outside,

  /// Not one of the weekdays a fixed schedule requires.
  notScheduled,

  /// After the day the commitment was broken.
  ended,

  /// The commitment is paused, completed or broken.
  unavailable,

  /// Past or today, unlogged, and still inside the backfill window: tap to log.
  unlogged,

  /// Past and unlogged, but the backfill window has closed.
  expired,

  /// A future day of the timeline.
  upcoming,
}

/// Human description of a [CalendarDayState] (screen readers, legends).
String calendarStateLabel(CalendarDayState state) => switch (state) {
  CalendarDayState.keptOnTime => 'Logged',
  CalendarDayState.keptLate => 'Logged late',
  CalendarDayState.broken => 'Broken',
  CalendarDayState.outside => 'Outside commitment',
  CalendarDayState.notScheduled => 'Not scheduled',
  CalendarDayState.ended => 'Commitment ended',
  CalendarDayState.unavailable => 'Check-ins unavailable',
  CalendarDayState.unlogged => 'Not logged',
  CalendarDayState.expired => 'Backfill window closed',
  CalendarDayState.upcoming => 'Upcoming',
};

/// Classifies [date] for [c]'s check-in calendar, as of [today] (in the
/// commitment's zone).
CalendarDayState apiCalendarState(
  Commitment c,
  List<CheckIn> checkIns,
  String date,
  String today,
) {
  final entry = apiCheckInOn(checkIns, c, date);
  if (entry != null && entry.outcome == CheckInOutcome.success) {
    final created = entry.createdAt;
    final late =
        created != null &&
        dateInZone(DateTime.parse(created), c.timeZone).compareTo(date) > 0;
    return late ? CalendarDayState.keptLate : CalendarDayState.keptOnTime;
  }
  if (entry != null && entry.outcome == CheckInOutcome.missed) {
    return CalendarDayState.broken;
  }
  if (date.compareTo(c.startDate) < 0 || date.compareTo(apiEndDate(c)) > 0) {
    return CalendarDayState.outside;
  }
  if (!_onSchedule(c.pace, date)) return CalendarDayState.notScheduled;
  final brokenOn = checkIns
      .where(
        (e) => e.attemptId == c.attemptId && e.outcome == CheckInOutcome.missed,
      )
      .map((e) => e.date)
      .firstOrNull;
  if (brokenOn != null && date.compareTo(brokenOn) > 0) {
    return CalendarDayState.ended;
  }
  if (c.status != CommitmentStatus.active) return CalendarDayState.unavailable;
  if (date.compareTo(today) <= 0) {
    return dayDifference(date, today) <= apiBackfillDays
        ? CalendarDayState.unlogged
        : CalendarDayState.expired;
  }
  return CalendarDayState.upcoming;
}

/// Whether the server will accept a new check-in for [date] right now.
bool canApiCheckIn(
  Commitment c,
  List<CheckIn> checkIns,
  String date,
  DateTime now,
) =>
    apiCalendarState(c, checkIns, date, dateInZone(now, c.timeZone)) ==
    CalendarDayState.unlogged;

// ---------------------------------------------------------------------------
// Today's tracking
// ---------------------------------------------------------------------------

/// One row of "Today's Tracking".
class ApiDueRow {
  const ApiDueRow({
    required this.commitment,
    required this.date,
    required this.catchUp,
  });

  /// The commitment to log against.
  final Commitment commitment;

  /// Today, or an earlier day still inside the backfill window.
  final String date;

  /// True when [date] is an earlier, unlogged day.
  final bool catchUp;
}

/// Everything the user can act on now: every commitment due today (logged or
/// not, so finished rows show their tick), plus, for every-day and
/// fixed-schedule habits, unlogged days from the backfill window whose
/// period is still open and unmet.
///
/// Order: today's rows first, unfinished before finished, oldest commitment
/// first, then by date.
List<ApiDueRow> apiDueRows(Snapshot snapshot, DateTime now) {
  final rows = <ApiDueRow>[];
  for (final c in snapshot.commitments) {
    final today = dateInZone(now, c.timeZone);
    // Catch-up rows only where each day matters (every day, or a fixed
    // schedule). Flexible paces can be met by logging today; their earlier
    // days stay available in the detail calendar.
    final everyDayCounts = c.pace is DailyPace || c.pace is CustomPace;
    for (var back = apiBackfillDays; back >= 1 && everyDayCounts; back--) {
      final date = addDays(today, -back);
      if (!canApiCheckIn(c, snapshot.checkIns, date, now)) continue;
      final period = apiProgress(c, snapshot.checkIns, now, onDate: date);
      if (period.periodSecured) continue;
      // A closed week no longer accepts progress on the server (only daily
      // periods have the two-day grace).
      if (c.pace is! DailyPace && period.periodEnd.compareTo(today) < 0) {
        continue;
      }
      rows.add(ApiDueRow(commitment: c, date: date, catchUp: true));
    }
    if (apiProgress(c, snapshot.checkIns, now).eligibleOnDate) {
      rows.add(ApiDueRow(commitment: c, date: today, catchUp: false));
    }
  }
  int done(ApiDueRow r) =>
      apiCheckInOn(snapshot.checkIns, r.commitment, r.date) == null ? 0 : 1;
  rows.sort((a, b) {
    final byCatchUp = (a.catchUp ? 1 : 0).compareTo(b.catchUp ? 1 : 0);
    if (byCatchUp != 0) return byCatchUp;
    final byDone = done(a).compareTo(done(b));
    if (byDone != 0) return byDone;
    final byCreated = a.commitment.createdAt.compareTo(b.commitment.createdAt);
    if (byCreated != 0) return byCreated;
    return a.date.compareTo(b.date);
  });
  return rows;
}

// ---------------------------------------------------------------------------
// Creation feasibility
// ---------------------------------------------------------------------------

/// Mirrors the server's `validatePeriodFeasibility`: every rule period that
/// intersects the timeline (including clipped first/last periods) must
/// contain at least as many eligible days as the target. Returns a friendly
/// error, or `null` when the plan is achievable.
String? apiFeasibilityError({
  required String startDate,
  required int duration,
  required Pace pace,
}) {
  final end = addDays(startDate, duration - 1);
  final target = switch (pace) {
    DailyPace() => 1,
    WeeklyPace(:final count) => count,
    CustomPace(:final days) => days.length,
    MonthlyPace(:final count) => count,
    WindowPace(:final targetCount) => targetCount,
  };
  var cursor = startDate;
  while (cursor.compareTo(end) <= 0) {
    final naturalEnd = switch (pace) {
      DailyPace() => cursor,
      WeeklyPace() || CustomPace() => addDays(cursor, 6 - dayOfWeek(cursor)),
      MonthlyPace() => _monthEnd(cursor),
      WindowPace(:final windowDays) => addDays(cursor, windowDays - 1),
    };
    final periodEnd = naturalEnd.compareTo(end) < 0 ? naturalEnd : end;
    var eligible = 0;
    for (
      var day = cursor;
      day.compareTo(periodEnd) <= 0;
      day = addDays(day, 1)
    ) {
      if (_onSchedule(pace, day)) eligible++;
    }
    if (eligible < target) {
      return 'The target cannot be met during ${formatShortDate(cursor)} – '
          '${formatShortDate(periodEnd)} (only $eligible eligible '
          'day${eligible == 1 ? '' : 's'} for a target of $target). '
          'Choose a lower target, a different start date, or a different '
          'schedule.';
    }
    cursor = addDays(periodEnd, 1);
  }
  return null;
}
