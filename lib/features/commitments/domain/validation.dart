/// Input validation for new commitments and check-ins.
///
/// These rules run in the UI (to show inline errors early) **and** inside the
/// repository (so bad data can never be stored, whatever the caller does).
/// Never rely on UI validation alone.
library;

import '../../../core/utils/calendar_date.dart';
import 'models.dart';
import 'schedule.dart';

/// A blank wizard draft: 30 days, "Everyday", starting today.
Draft freshDraft([DateTime? now]) => Draft(
  path: null,
  name: '',
  description: '',
  startDate: dateInZone(now ?? DateTime.now()),
  duration: 30,
  pace: const DailyPace(1),
  reward: '',
);

/// Returns [d] with its start date moved to today if that date has passed.
///
/// A draft can be saved on Monday and reopened on Wednesday. Its Monday start
/// date would now fail validation ("choose today or later") and the user would
/// be stuck on the review step. The challenge keeps its length; only the start
/// moves forward.
Draft withCurrentStart(Draft d, [DateTime? now]) {
  final today = dateInZone(now ?? DateTime.now());
  return d.startDate.compareTo(today) < 0 ? d.copyWith(startDate: today) : d;
}

/// Checks a whole [Draft]. Returns a friendly error message, or `null` when
/// the draft is valid.
String? validateDraft(Draft d, [DateTime? now]) {
  final clock = now ?? DateTime.now();
  if (d.path == null) return 'Choose Build or Quit to continue.';
  if (d.name.trim().isEmpty || d.name.trim().length > 80) {
    return 'Give your commitment a name between 1 and 80 characters.';
  }
  if (d.description.length > 300) {
    return 'Keep the description within 300 characters.';
  }
  if (!isValidDate(d.startDate) ||
      d.startDate.compareTo(dateInZone(clock)) < 0) {
    return 'Choose today or a future start date.';
  }
  if (d.duration < 1 || d.duration > 365) {
    return 'Choose a duration between 1 and 365 days.';
  }
  switch (d.pace) {
    case CustomPace(:final days):
      final valid =
          days.isNotEmpty &&
          days.every((n) => n >= 0 && n <= 6) &&
          days.toSet().length == days.length;
      if (!valid) return 'Choose at least one valid weekday.';
      // At least one chosen weekday must actually occur inside the challenge.
      final occurs = List.generate(
        d.duration,
        (i) => dayOfWeek(addDays(d.startDate, i)),
      ).any(days.contains);
      if (!occurs) return 'Choose days that occur during your challenge.';
    case DailyPace(:final count):
      final max = d.path == HabitPath.quit ? 1 : 99;
      if (count < 1 || count > max) return 'Choose a valid execution target.';
    case WeeklyPace(:final count):
      if (count < 1 || count > 7) return 'Choose a valid execution target.';
    case MonthlyPace(:final count):
      if (count < 1 || count > 31) return 'Choose a valid execution target.';
    case WindowPace(:final targetCount, :final windowDays):
      if (windowDays < 1 ||
          windowDays > 365 ||
          targetCount < 1 ||
          targetCount > windowDays) {
        return 'Choose a valid execution target.';
      }
  }
  if (d.reward.trim().isEmpty || d.reward.trim().length > 120) {
    return 'Choose a reward, up to 120 characters.';
  }
  return null;
}

/// Throws a [LockInException] unless [count] may be saved for [date] now.
///
/// Counts are absolute (not "add one"), between 0 and the day's target.
void validateCheckIn(Commitment c, String date, int count, DateTime now) {
  if (!canLog(c, date, now)) {
    throw const LockInException('This date is outside its check-in window.');
  }
  if (count < 0 || count > targetForDate(c)) {
    throw const LockInException('Choose a count within your daily target.');
  }
}
