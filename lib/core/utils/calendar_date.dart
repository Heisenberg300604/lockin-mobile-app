/// Calendar-date helpers used by every part of the app.
///
/// ## Why dates are `String`s
///
/// A habit's schedule is made of *calendar days* ("the 4th of June"), not of
/// moments in time. Using a `DateTime` for those is a classic source of bugs:
/// a `DateTime` silently carries a time zone and a time of day, so "June 4th"
/// can turn into "June 3rd" the moment you convert between UTC and local time.
///
/// So the app stores calendar days as plain `yyyy-MM-dd` strings (for example
/// `"2026-06-04"`). They compare correctly with `<` / `>` (lexicographic order
/// equals chronological order), they serialise to JSON for free, and they can
/// never drift by a day. The same representation is used by the original React
/// Native app, which keeps stored data and (future) backend payloads compatible.
///
/// Whenever we need a real instant (for example "when does the 24 hour
/// catch-up window end?"), we convert a calendar day plus an IANA time zone
/// (like `Asia/Kolkata`) into an instant with [midnight].
library;

import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// Milliseconds in 24 hours. A "day" for catch-up purposes is exactly 24
/// elapsed hours, even across daylight-saving changes.
const int msPerDay = 86400000;

/// Holds the IANA zone of the device (for example `Asia/Kolkata`).
///
/// It is resolved once at start-up (see `bootstrap.dart`) because reading it
/// is asynchronous, while the domain rules that need it are synchronous.
/// Everything else receives the zone explicitly; only "today in the user's own
/// zone" defaults to this value.
abstract final class DeviceZone {
  /// Defaults to UTC so unit tests and early start-up code behave predictably.
  static String current = 'UTC';
}

/// The IANA time zone of the device.
String deviceZone() => DeviceZone.current;

/// Looks up an IANA zone. The bundled database has no plain `UTC` entry, so
/// that one is mapped to the built-in constant.
tz.Location locationFor(String timeZone) =>
    timeZone == 'UTC' ? tz.UTC : tz.getLocation(timeZone);

/// Parses a `yyyy-MM-dd` day as noon UTC.
///
/// Noon (instead of midnight) is deliberate: adding or subtracting whole days
/// can never cross a date boundary because of a leap second or a DST shift.
DateTime _noonUtc(String date) => DateTime.parse('${date}T12:00:00Z');

String _format(DateTime utc) {
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Returns the calendar day [days] after [date] (negative goes backwards).
String addDays(String date, int days) {
  final shifted = _noonUtc(date).add(Duration(days: days));
  return _format(shifted);
}

/// Whole number of days from [a] to [b] (positive when [b] is later).
int dayDifference(String a, String b) {
  final ms = _noonUtc(b).millisecondsSinceEpoch - _noonUtc(a).millisecondsSinceEpoch;
  return (ms / msPerDay).round();
}

/// True when [date] is a real calendar day written as `yyyy-MM-dd`.
///
/// `2026-02-30` has the right *shape* but is not a real day, so after parsing
/// we round-trip it and make sure nothing changed.
bool isValidDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
  final parsed = DateTime.tryParse('${date}T12:00:00Z');
  return parsed != null && addDays(date, 0) == date;
}

/// Day of the week where Monday is 0 and Sunday is 6.
///
/// The app shows weeks starting on Monday, so every weekday number stored in a
/// "Custom Days" pace uses this convention.
int dayOfWeek(String date) => _noonUtc(date).weekday - 1;

/// The calendar day that [now] falls on in [timeZone].
///
/// Example: `2026-06-04T20:00Z` is already `2026-06-05` in `Asia/Kolkata`.
String dateInZone(DateTime now, [String? timeZone]) {
  final location = locationFor(timeZone ?? deviceZone());
  return _format(_wallClock(tz.TZDateTime.from(now, location)));
}

DateTime _wallClock(tz.TZDateTime t) => DateTime.utc(t.year, t.month, t.day);

/// The instant (milliseconds since epoch, UTC) at which [date] starts in
/// [timeZone].
///
/// `timezone`'s [tz.TZDateTime] resolves DST gaps and overlaps for us, so
/// "midnight" is always a real instant.
int midnight(String date, String timeZone) {
  final d = _noonUtc(date);
  final location = locationFor(timeZone);
  return tz.TZDateTime(location, d.year, d.month, d.day).millisecondsSinceEpoch;
}

// ---------------------------------------------------------------------------
// Formatting (always English, matching the original app)
// ---------------------------------------------------------------------------

/// `Jun 4, 2026`
String formatDate(String date) => DateFormat('MMM d, y').format(_noonUtc(date));

/// `Jun 4`
String formatShortDate(String date) => DateFormat('MMM d').format(_noonUtc(date));

/// `June 2026`
String formatMonthYear(String date) => DateFormat('MMMM y').format(_noonUtc(date));

/// Short weekday names, Monday first. Index = [dayOfWeek] result.
const List<String> weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
