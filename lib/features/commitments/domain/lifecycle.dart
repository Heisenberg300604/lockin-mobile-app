/// State transitions of an attempt: pause, resume, fail, restart, expire,
/// complete.
///
/// ```text
///            pause                     explicit failure / expired window
///   Active ─────────▶ Paused      Active ───────────────────────────────▶ Broken
///     ▲  ◀───────────  │                 time runs out, all done            │
///     │     resume     │          Active ───────────────▶ Completed         │ restart
///     └────────────────┘                                                    ▼
///                                                            (a NEW Active attempt)
/// ```
///
/// Like `schedule.dart`, everything is a pure function. Functions that change
/// data **return a new object** instead of editing the old one; the caller
/// (the repository) decides when to save it. If anything throws, nothing was
/// changed, which gives us "all or nothing" updates for free.
library;

import '../../../core/utils/calendar_date.dart';
import 'models.dart';
import 'schedule.dart';

/// Returns [c] with one more dated event in its history.
Commitment withEvent(
  Commitment c,
  LifecycleEventType type,
  DateTime now, [
  String? date,
]) =>
    c.copyWith(
      events: [
        ...c.events,
        LifecycleEvent(
          type: type,
          at: now.toUtc().toIso8601String(),
          date: date ?? dateInZone(now, c.timeZone),
        ),
      ],
    );

Commitment _breakAttempt(
  Commitment c,
  String date,
  FailureReason reason,
  DateTime now,
) =>
    withEvent(
      c.copyWith(
        status: CommitmentStatus.broken,
        failureDate: date,
        failureReason: reason,
      ),
      LifecycleEventType.broken,
      now,
      date,
    );

/// Applies the time-based rules ("expiry" and "completion") to the whole
/// [data] as of [now].
///
/// Nothing in the app moves an attempt to broken/completed on a timer. Instead
/// this function is run whenever data is read or written, so the result is the
/// same no matter when the app was last open. It is **idempotent**: running it
/// twice changes nothing the second time.
///
/// Returns the very same [data] instance when nothing changed, so callers can
/// detect a change with `identical(before, after)`.
Snapshot reconcile(Snapshot data, DateTime now) {
  var changed = false;
  final next = <Commitment>[];
  for (final c in data.commitments) {
    final updated = _reconcileOne(c, data.checkIns, now);
    if (!identical(updated, c)) changed = true;
    next.add(updated);
  }
  return changed ? data.copyWith(commitments: next) : data;
}

Commitment _reconcileOne(Commitment original, List<CheckIn> checkIns, DateTime now) {
  var c = original;
  if (c.status != CommitmentStatus.active && c.status != CommitmentStatus.paused) {
    return c;
  }
  final dates = activeDates(c);
  final nowMs = now.millisecondsSinceEpoch;
  var satisfied = true;

  if (c.pace is WeeklyPace) {
    // Weekly: evaluate each *full* period once its last day's window closed.
    for (var i = 0; i < dates.length; i += 7) {
      final part = dates.skip(i).take(7).toList();
      final expected = (c.duration - i) < 7 ? c.duration - i : 7;
      final full = part.length == expected;
      final done = progress(c, checkIns, part.first).done;
      if (!full || !done) satisfied = false;
      if (full && !done && nowMs >= deadline(c, part.last)) {
        c = _breakAttempt(c, part.last, FailureReason.quota, now);
        break;
      }
    }
  } else {
    // Daily / custom: the first unmet day whose window closed breaks it.
    for (final date in dates.where((d) => isScheduled(c, d))) {
      final done = (getLog(checkIns, c, date)?.count ?? 0) >= targetForDate(c);
      if (!done) satisfied = false;
      if (!done && nowMs >= deadline(c, date)) {
        c = _breakAttempt(c, date, FailureReason.missed, now);
        break;
      }
    }
  }

  // Completion: every planned day has happened, all requirements are met, and
  // the final day is over (we do not wait for the unused catch-up time).
  if (c.status == CommitmentStatus.active &&
      dates.length == c.duration &&
      satisfied &&
      nowMs >= midnight(addDays(endDate(c), 1), c.timeZone)) {
    c = withEvent(
      c.copyWith(
        status: CommitmentStatus.completed,
        completedAt: now.toUtc().toIso8601String(),
      ),
      LifecycleEventType.completed,
      now,
      endDate(c),
    );
  }
  return c;
}

/// Pauses [c] **from tomorrow**.
///
/// Today's target still counts (so logs already made today are never lost),
/// and earlier catch-up windows keep their deadlines. Throws a
/// [LockInException] if the attempt cannot be paused (see [canPause]).
Commitment pauseCommitment(Commitment c, DateTime now) {
  if (!canPause(c, now)) {
    throw const LockInException(
      'Only a started commitment with days remaining can be paused.',
    );
  }
  final tomorrow = addDays(dateInZone(now, c.timeZone), 1);
  return withEvent(
    c.copyWith(
      status: CommitmentStatus.paused,
      pauses: [...c.pauses, PauseInterval(start: tomorrow)],
    ),
    LifecycleEventType.paused,
    now,
  );
}

/// Resumes a paused attempt. The frozen interval runs from the pause start up
/// to (excluding) today, and the end date moves out by that many days.
Commitment resumeCommitment(Commitment c, DateTime now) {
  if (c.status != CommitmentStatus.paused) {
    throw const LockInException(
      'This commitment can no longer be resumed. Refresh to see its status.',
    );
  }
  final openIndex = c.pauses.indexWhere((p) => p.end == null);
  if (openIndex < 0) {
    throw const LockInException('The saved pause could not be found.');
  }
  final open = c.pauses[openIndex];
  final today = dateInZone(now, c.timeZone);
  // Resuming on the same day as the pause (before the freeze starts) adds zero
  // frozen days rather than a negative number.
  final end = today.compareTo(open.start) < 0 ? open.start : today;
  final pauses = [...c.pauses]..[openIndex] = open.closedOn(end);
  return withEvent(
    c.copyWith(status: CommitmentStatus.active, pauses: pauses),
    LifecycleEventType.resumed,
    now,
  );
}

/// Records an explicit "missed / broke my commitment" for [date].
///
/// For daily and custom paces this ends the attempt immediately. For weekly
/// quotas it only records the day: the attempt breaks later, and only if the
/// period finishes below its quota.
Snapshot failDay(Snapshot data, Commitment c, String date, DateTime now) {
  if (!canLog(c, date, now)) {
    throw const LockInException('This date is outside its check-in window.');
  }
  final log = CheckIn(
    attemptId: c.attemptId,
    date: date,
    count: 0,
    outcome: CheckInOutcome.missed,
    updatedAt: now.toUtc().toIso8601String(),
  );
  final checkIns = [...data.checkIns];
  final i = checkIns.indexWhere((l) => l.attemptId == c.attemptId && l.date == date);
  if (i < 0) {
    checkIns.add(log);
  } else {
    checkIns[i] = log;
  }
  var next = data.copyWith(checkIns: checkIns);
  if (c.pace is! WeeklyPace) {
    next = _replace(next, _breakAttempt(c, date, FailureReason.explicit, now));
  }
  return next;
}

/// Result of [restartAttempt]: the updated data plus the new attempt.
typedef RestartResult = ({Snapshot snapshot, Commitment attempt});

/// Restarts a broken attempt as a **new linked attempt** with the same rules,
/// starting today. The old attempt is kept (with the reflection attached) so
/// history stays complete.
///
/// Idempotent: calling again for an attempt that was already restarted returns
/// the existing replacement instead of creating a second one.
RestartResult restartAttempt(
  Snapshot data,
  Commitment c,
  String requestId,
  String reason,
  String note,
  DateTime now,
) {
  final replacementId = c.restartedBy;
  if (replacementId != null) {
    final existing = data.commitments.firstWhere((x) => x.attemptId == replacementId);
    return (snapshot: data, attempt: existing);
  }
  if (c.status != CommitmentStatus.broken) {
    throw const LockInException('Only a broken commitment can be restarted.');
  }
  if (reason.length > 80 || note.length > 500) {
    throw const LockInException('Keep your reflection within 500 characters.');
  }
  if (data.commitments.any((x) => x.id == requestId)) {
    throw const LockInException(
      'This request was already used. Reopen this screen and retry.',
    );
  }
  final today = dateInZone(now, c.timeZone);
  final fresh = withEvent(
    Commitment(
      id: requestId,
      attemptId: requestId,
      commitmentId: c.commitmentId ?? c.id,
      previousAttemptId: c.attemptId,
      name: c.name,
      description: c.description,
      path: c.path,
      duration: c.duration,
      pace: c.pace, // Pace objects are immutable, so sharing is safe.
      reward: c.reward,
      timeZone: c.timeZone,
      startDate: today,
      status: CommitmentStatus.active,
      createdAt: now.toUtc().toIso8601String(),
    ),
    LifecycleEventType.locked,
    now,
  );
  final old = withEvent(
    c.copyWith(
      reflection: Reflection(
        reason: reason.trim(),
        note: note.trim(),
        savedAt: now.toUtc().toIso8601String(),
      ),
      restartedBy: requestId,
    ),
    LifecycleEventType.restarted,
    now,
  );
  final replaced = _replace(data, old);
  return (
    snapshot: replaced.copyWith(commitments: [fresh, ...replaced.commitments]),
    attempt: fresh,
  );
}

Snapshot _replace(Snapshot data, Commitment updated) => data.copyWith(
      commitments: [
        for (final c in data.commitments) c.attemptId == updated.attemptId ? updated : c,
      ],
    );
