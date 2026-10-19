/// The scheduling rules: "which days is this habit due, and how am I doing?"
///
/// Everything here is a **pure function**: same inputs, same output, no
/// storage, no clock reads (the current time is always passed in as `now`).
/// That makes the rules easy to test and easy to reason about.
///
/// The authoritative description of these rules is the original project's
/// `docs/behavior-spec.md`; each function below cites the rule it implements.
library;

import '../../../core/utils/calendar_date.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Timeline: end date, paused days, active days
// ---------------------------------------------------------------------------

/// Last planned day for a challenge starting on [startDate] and lasting
/// [duration] days, pushed back by every *finished* pause in [pauses].
///
/// Rule: duration N means N non-paused calendar days **including** the start
/// day, so without pauses `end = start + N - 1`. A 45 day challenge starting
/// June 4 ends July 18.
///
/// A pause that is still open (no `end`) is ignored here: its final length is
/// unknown, so the deadline only moves once the user resumes.
String computeEndDate(
  String startDate,
  int duration,
  List<PauseInterval> pauses,
) {
  var frozen = 0;
  for (final p in pauses) {
    final end = p.end;
    if (end != null) {
      final length = dayDifference(p.start, end);
      if (length > 0) frozen += length;
    }
  }
  return addDays(startDate, duration - 1 + frozen);
}

/// [computeEndDate] for a saved [Commitment].
String endDate(Commitment c) =>
    computeEndDate(c.startDate, c.duration, c.pauses);

/// [computeEndDate] for a wizard [Draft] (which has no pauses).
String draftEndDate(Draft d) =>
    computeEndDate(d.startDate, d.duration, const []);

/// Whether [date] falls inside any pause (open pauses extend forever).
bool isPausedDate(Commitment c, String date) => c.pauses.any((p) {
  final end = p.end;
  return date.compareTo(p.start) >= 0 &&
      (end == null || date.compareTo(end) < 0);
});

/// Every day on which the attempt is "running": from the start date to the end
/// date, minus paused days. If an open pause exists the list stops at it.
///
/// The number of entries up to a given day is the "Day N" shown in the UI.
List<String> activeDates(Commitment c) {
  final result = <String>[];
  final end = endDate(c);
  for (
    var date = c.startDate;
    date.compareTo(end) <= 0;
    date = addDays(date, 1)
  ) {
    if (!isPausedDate(c, date)) result.add(date);
    final openPauseStarted = c.pauses.any(
      (p) => p.end == null && date.compareTo(p.start) >= 0,
    );
    if (openPauseStarted) break;
  }
  return result;
}

/// The "Day N" ordinal for [date]. It freezes while paused and stops counting
/// at the failure date, so a broken attempt never shows "Day 6" for day 9.
int dayOrdinal(Commitment c, String date) {
  final failure = c.failureDate;
  final cutoff = failure != null && failure.compareTo(date) < 0
      ? failure
      : date;
  return activeDates(c).where((d) => d.compareTo(cutoff) <= 0).length;
}

/// Pausing is only offered for a running attempt that has already started and
/// still has at least one planned day after today.
bool canPause(Commitment c, DateTime now) {
  final today = dateInZone(now, c.timeZone);
  return c.status == CommitmentStatus.active &&
      today.compareTo(c.startDate) >= 0 &&
      today.compareTo(endDate(c)) < 0;
}

// ---------------------------------------------------------------------------
// The 24 hour catch-up window
// ---------------------------------------------------------------------------

/// The instant at which the window for logging [date] closes: the *end* of
/// that day in the attempt's zone plus exactly 24 elapsed hours.
///
/// Rule: "The end of date D is the start of D+1 in the attempt's zone. Its
/// catch-up deadline is that instant plus exactly 24 hours." Adding raw
/// milliseconds (not calendar days) keeps it 24 real hours across DST changes.
int deadline(Commitment c, String date) =>
    midnight(addDays(date, 1), c.timeZone) + msPerDay;

/// Whether [date] is a day the habit is due (inside the timeline, not paused,
/// and, for Custom Days, one of the chosen weekdays).
bool isScheduled(Commitment c, String date) {
  if (date.compareTo(c.startDate) < 0) return false;
  if (date.compareTo(endDate(c)) > 0) return false;
  if (isPausedDate(c, date)) return false;
  final pace = c.pace;
  if (pace is CustomPace) return pace.days.contains(dayOfWeek(date));
  return true;
}

/// Whether the user may still record a result for [date] right now.
///
/// All of these must hold: the attempt is running (active or paused, so an
/// outstanding obligation can still be settled), the day is scheduled, it is
/// not in the future, and its catch-up deadline has not passed.
bool canLog(Commitment c, String date, DateTime now) {
  final running =
      c.status == CommitmentStatus.active ||
      c.status == CommitmentStatus.paused;
  return running &&
      isScheduled(c, date) &&
      date.compareTo(dateInZone(now, c.timeZone)) <= 0 &&
      now.millisecondsSinceEpoch < deadline(c, date);
}

/// Whether the deployed API accepts a check-in. Unlike the legacy local
/// workflow, the server accepts only one result for the commitment's current
/// time-zone date; it has no catch-up endpoint.
bool canApiCheckIn(Commitment c, String date, DateTime now) {
  final today = dateInZone(now, c.timeZone);
  return c.status == CommitmentStatus.active &&
      date == today &&
      isScheduled(c, date);
}

/// Repetitions needed on a single day: the daily count, otherwise 1.
int targetForDate(Commitment c) {
  final pace = c.pace;
  return pace is DailyPace ? pace.count : 1;
}

/// Human label for a pace, e.g. "Everyday", "3 days per week", "Mon, Wed".
String paceLabel(Pace pace) => switch (pace) {
  DailyPace(:final count) => count == 1 ? 'Everyday' : '$count times a day',
  WeeklyPace(:final count) => '$count days per week',
  CustomPace(:final days) => ([
    ...days,
  ]..sort()).map((d) => weekdayNames[d]).join(', '),
  MonthlyPace(:final count) => '$count days per month',
  WindowPace(:final targetCount, :final windowDays) =>
    '$targetCount days every $windowDays days',
};

/// The saved check-in of [c] for [date], or `null`.
CheckIn? getLog(List<CheckIn> logs, Commitment c, String date) {
  for (final l in logs) {
    if (l.attemptId == c.attemptId && l.date == date) return l;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Weekly quota periods
// ---------------------------------------------------------------------------

/// The weekly period that contains [date].
///
/// Periods are **seven active days counted from the attempt's start**, not
/// calendar weeks, and paused days do not count (a pause suspends the period).
/// `required` is the number of distinct successful days needed. For a short
/// final period it is prorated *upward*: `ceil(N * days / 7)`.
({String start, String end, int required}) weeklyPeriod(
  Commitment c,
  String date,
) {
  final dates = activeDates(c);
  final upToDate = dates.where((d) => d.compareTo(date) <= 0).length;
  final ordinal = upToDate - 1 < 0 ? 0 : upToDate - 1;
  final offset = (ordinal ~/ 7) * 7;
  final periodDates = dates.skip(offset).take(7).toList();
  final start = periodDates.isEmpty ? c.startDate : periodDates.first;
  final end = periodDates.isEmpty ? start : periodDates.last;
  final pace = c.pace;
  var required = 1;
  if (pace is WeeklyPace) {
    final daysInPeriod = (c.duration - offset) < 7 ? c.duration - offset : 7;
    // Integer ceil(a / 7) without floating point.
    required = (pace.count * daysInPeriod + 6) ~/ 7;
  }
  return (start: start, end: end, required: required);
}

/// How far along the user is for [date]: `count` of `target`, and whether that
/// target is met.
///
/// * Daily / custom paces: the saved count for that day versus the target.
/// * Weekly pace: the number of **distinct** successful days in the period
///   (several repetitions on one day still count once).
({int count, int target, bool done}) progress(
  Commitment c,
  List<CheckIn> logs,
  String date,
) {
  if (c.pace is WeeklyPace) {
    final period = weeklyPeriod(c, date);
    final days = <String>{};
    for (final l in logs) {
      if (l.attemptId == c.attemptId &&
          l.date.compareTo(period.start) >= 0 &&
          l.date.compareTo(period.end) <= 0 &&
          isScheduled(c, l.date) &&
          l.count >= 1) {
        days.add(l.date);
      }
    }
    return (
      count: days.length,
      target: period.required,
      done: days.length >= period.required,
    );
  }
  final count = getLog(logs, c, date)?.count ?? 0;
  final target = targetForDate(c);
  return (count: count, target: target, done: count >= target);
}

// ---------------------------------------------------------------------------
// "What is due today?" and streaks
// ---------------------------------------------------------------------------

/// One row of the "Today's Tracking" list.
class DueRow {
  /// Creates a row.
  const DueRow({
    required this.commitment,
    required this.date,
    required this.catchUp,
  });

  /// The attempt to log against.
  final Commitment commitment;

  /// The day to log (today, or an earlier day still inside its window).
  final String date;

  /// True when [date] is an earlier day being caught up.
  final bool catchUp;
}

/// Everything the user can act on right now: today's tasks, plus unfinished
/// tasks from the previous two days whose catch-up window is still open.
///
/// Order: today's work before catch-up, unfinished before finished, then
/// oldest commitment first (ties by date so the order is deterministic).
List<DueRow> dueRows(Snapshot snapshot, DateTime now) {
  final rows = <DueRow>[];
  for (final c in snapshot.commitments) {
    final today = dateInZone(now, c.timeZone);
    for (final date in [addDays(today, -2), addDays(today, -1), today]) {
      if (!canLog(c, date, now)) continue;
      if (date != today && progress(c, snapshot.checkIns, date).done) continue;
      rows.add(DueRow(commitment: c, date: date, catchUp: date != today));
    }
  }
  int doneFlag(DueRow r) =>
      progress(r.commitment, snapshot.checkIns, r.date).done ? 1 : 0;
  rows.sort((a, b) {
    final byCatchUp = (a.catchUp ? 1 : 0).compareTo(b.catchUp ? 1 : 0);
    if (byCatchUp != 0) return byCatchUp;
    final byDone = doneFlag(a).compareTo(doneFlag(b));
    if (byDone != 0) return byDone;
    final byCreated = a.commitment.createdAt.compareTo(b.commitment.createdAt);
    if (byCreated != 0) return byCreated;
    return a.date.compareTo(b.date);
  });
  return rows;
}

/// Today's server-backed tracking rows. Kept separate from [dueRows] so the
/// legacy local repository remains testable without exposing unsupported
/// catch-up actions in the production UI.
List<DueRow> apiDueRows(Snapshot snapshot, DateTime now) {
  final rows = <DueRow>[];
  for (final commitment in snapshot.commitments) {
    final today = dateInZone(now, commitment.timeZone);
    if (canApiCheckIn(commitment, today, now)) {
      rows.add(DueRow(commitment: commitment, date: today, catchUp: false));
    }
  }
  rows.sort((a, b) => a.commitment.createdAt.compareTo(b.commitment.createdAt));
  return rows;
}

/// The current streak and the unit it is measured in.
///
/// Daily/custom: consecutive successful scheduled days (an unresolved *today*
/// neither adds nor breaks it). Weekly: consecutive completed full periods.
({int count, String unit}) streak(
  Commitment c,
  List<CheckIn> logs,
  DateTime now,
) {
  final today = dateInZone(now, c.timeZone);
  final dates = activeDates(c);
  var count = 0;
  if (c.pace is WeeklyPace) {
    for (var i = 0; i < dates.length; i += 7) {
      final remaining = c.duration - i;
      final expected = remaining < 7 ? remaining : 7;
      final part = dates.skip(i).take(7).toList();
      if (part.length != expected || part.last.compareTo(today) >= 0) break;
      count = progress(c, logs, part.first).done ? count + 1 : 0;
    }
    return (count: count, unit: 'quota periods');
  }
  for (final date in dates.where(
    (d) => d.compareTo(today) <= 0 && isScheduled(c, d),
  )) {
    final log = getLog(logs, c, date);
    if ((log?.count ?? 0) >= targetForDate(c)) {
      count++;
    } else if (date != today ||
        log?.outcome == CheckInOutcome.missed ||
        c.failureDate == date) {
      count = 0;
    }
  }
  return (count: count, unit: 'scheduled days');
}
