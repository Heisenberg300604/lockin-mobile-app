/// Decides **which reminders should exist** for the current data.
///
/// This file only *plans*; it never talks to the operating system. The plan is
/// a pure function of (data, preferred time, now), so it can be unit-tested and
/// simply recomputed whenever anything changes. A separate scheduler
/// (`reminder_scheduler.dart`) makes the phone's notifications match the plan.
///
/// Reminders are only a convenience. They are never used to decide whether a
/// commitment is broken (that is `reconcile` in lifecycle.dart).
library;

import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/calendar_date.dart';
import '../../commitments/domain/models.dart';
import '../../commitments/domain/schedule.dart';

/// One notification to show at an exact instant.
class Reminder {
  /// Creates a reminder.
  const Reminder({
    required this.key,
    required this.attemptId,
    required this.date,
    required this.at,
  });

  /// Stable identity, e.g. `lockin:<attempt>:<date>:<onDate>:<time>`. If a
  /// reminder with the same key already exists on the phone it is kept as is.
  final String key;

  /// The attempt it opens when tapped.
  final String attemptId;

  /// The day it is a reminder *for*.
  final String date;

  /// When to show it (milliseconds since epoch, UTC).
  final int at;
}

/// The instant when the wall clock in [timeZone] reads [time] ("HH:mm") on
/// [date], or `null` if that wall-clock time does not exist (it is skipped by a
/// spring-forward DST jump).
///
/// "20:00" stays 20:00 local time through DST changes and travel.
int? reminderInstant(String date, String time, String timeZone) {
  final parts = time.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  final d = DateTime.parse('${date}T12:00:00Z');
  final location = locationFor(timeZone);
  final t = tz.TZDateTime(location, d.year, d.month, d.day, hour, minute);
  // If the clock skipped this time, TZDateTime silently moves it. Detect that
  // and refuse rather than reminding at a different time.
  if (t.hour != hour || t.minute != minute || t.day != d.day) return null;
  return t.millisecondsSinceEpoch;
}

/// Builds the list of reminders to schedule (at most 60, soonest first).
///
/// For every unfinished scheduled day within the next 30 days (and the last
/// two), we plan one reminder on the day itself and one catch-up reminder the
/// next day, both at the user's chosen [time]. Nothing is planned at or after
/// the moment the earliest unresolved day would break the attempt.
List<Reminder> reminderPlan(Snapshot snapshot, String time, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final plan = <Reminder>[];

  for (final c in snapshot.commitments) {
    if (c.status != CommitmentStatus.active || c.restartedBy != null) continue;
    final today = dateInZone(now, c.timeZone);
    final dates = activeDates(c);

    // `cutoff`: the deadline of the earliest unresolved obligation. A reminder
    // after it would nag about something that is already lost.
    var cutoff = double.infinity;
    if (c.pace is WeeklyPace) {
      for (var i = 0; i < dates.length; i += 7) {
        final part = dates.skip(i).take(7).toList();
        if (!progress(c, snapshot.checkIns, part.first).done) {
          cutoff = deadline(c, part.last).toDouble();
          break;
        }
      }
    } else {
      for (final d in dates) {
        if (isScheduled(c, d) &&
            (getLog(snapshot.checkIns, c, d)?.count ?? 0) < targetForDate(c)) {
          cutoff = deadline(c, d).toDouble();
          break;
        }
      }
    }

    for (final date in dates) {
      if (!isScheduled(c, date) ||
          (getLog(snapshot.checkIns, c, date)?.count ?? 0) >= targetForDate(c) ||
          progress(c, snapshot.checkIns, date).done ||
          date.compareTo(addDays(today, -2)) < 0 ||
          date.compareTo(addDays(today, 30)) > 0) {
        continue;
      }
      // A daily reminder plus one catch-up reminder, both bound by `cutoff`.
      for (final onDate in [date, addDays(date, 1)]) {
        final at = reminderInstant(onDate, time, c.timeZone);
        if (at == null || at <= nowMs || at >= deadline(c, date) || at >= cutoff) {
          continue;
        }
        plan.add(Reminder(
          key: 'lockin:${c.attemptId}:$date:$onDate:$time',
          attemptId: c.attemptId,
          date: date,
          at: at,
        ));
      }
    }
  }

  plan.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    if (byTime != 0) return byTime;
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.key.compareTo(b.key);
  });

  // Only one reminder per attempt per instant.
  final seen = <String>{};
  final unique = <Reminder>[];
  for (final r in plan) {
    if (seen.add('${r.attemptId}:${r.at}')) unique.add(r);
  }
  return unique.take(60).toList();
}
