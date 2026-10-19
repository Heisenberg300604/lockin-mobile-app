/// Progress calculations that match the deployed LockIn API contract.
library;

import '../../../core/utils/calendar_date.dart';
import 'models.dart';

/// Progress for the current API rule period and lifetime duration.
class ApiProgress {
  const ApiProgress({
    required this.durationDays,
    required this.elapsedDays,
    required this.daysRemaining,
    required this.elapsedPercent,
    required this.successfulCheckIns,
    required this.periodProgress,
    required this.periodTarget,
    required this.periodLabel,
    required this.checkedToday,
    required this.eligibleToday,
  });

  final int durationDays;
  final int elapsedDays;
  final int daysRemaining;
  final int elapsedPercent;
  final int successfulCheckIns;
  final int periodProgress;
  final int periodTarget;
  final String periodLabel;
  final bool checkedToday;
  final bool eligibleToday;
}

/// Calculates progress using date-only strings. Response dates must already
/// have been normalised by taking their first ten characters.
ApiProgress apiProgress(
  Commitment commitment,
  List<CheckIn> checkIns,
  DateTime now,
) {
  final today = dateInZone(now, commitment.timeZone);
  final end = addDays(commitment.startDate, commitment.duration - 1);
  final duration = commitment.duration;
  final elapsed = today.compareTo(commitment.startDate) < 0
      ? 0
      : (dayDifference(commitment.startDate, today) + 1).clamp(0, duration);
  final reference = today.compareTo(commitment.startDate) < 0
      ? commitment.startDate
      : (today.compareTo(end) > 0 ? end : today);
  final period = _periodFor(commitment, reference);
  final kept = checkIns
      .where(
        (checkIn) =>
            checkIn.attemptId == commitment.id &&
            checkIn.outcome == CheckInOutcome.success,
      )
      .toList();
  final inPeriod = kept.where(
    (checkIn) =>
        checkIn.date.compareTo(period.start) >= 0 &&
        checkIn.date.compareTo(period.end) <= 0,
  );
  final scheduled = commitment.pace is CustomPace
      ? (commitment.pace as CustomPace).days.map((day) => day + 1).toSet()
      : const <int>{};
  final eligible =
      commitment.status == CommitmentStatus.active &&
      today.compareTo(commitment.startDate) >= 0 &&
      today.compareTo(end) <= 0 &&
      (scheduled.isEmpty || scheduled.contains(dayOfWeek(today) + 1));

  return ApiProgress(
    durationDays: duration,
    elapsedDays: elapsed,
    daysRemaining: duration - elapsed,
    elapsedPercent: ((elapsed / duration) * 100).round(),
    successfulCheckIns: kept.length,
    periodProgress: inPeriod.length,
    periodTarget: period.target,
    periodLabel: period.label,
    checkedToday: checkIns.any(
      (checkIn) => checkIn.attemptId == commitment.id && checkIn.date == today,
    ),
    eligibleToday: eligible,
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
    final parsed = DateTime.parse('${date}T12:00:00Z');
    final start =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-01';
    final nextMonth = DateTime.utc(parsed.year, parsed.month + 1, 1);
    return (
      start: start,
      end: addDays(_formatDate(nextMonth), -1),
      target: pace.count,
      label: 'This month',
    );
  }
  if (pace is WindowPace) {
    final offset = dayDifference(c.startDate, date);
    final block = offset ~/ pace.windowDays;
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

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
