/// Shared helpers for the domain tests.
library;

import 'package:lockin/features/commitments/data/key_value_store.dart';
import 'package:lockin/features/commitments/domain/models.dart';
import 'package:timezone/data/latest.dart' as tzdata;

bool _initialised = false;

/// Loads the IANA time-zone database once. Must be called before any test that
/// touches dates in a time zone.
void initTimeZones() {
  if (_initialised) return;
  tzdata.initializeTimeZones();
  _initialised = true;
}

/// Noon UTC on [date]; a convenient "now" for lifecycle tests.
DateTime at(String date) => DateTime.parse('${date}T12:00:00Z');

/// A baseline 7-day, everyday, UTC commitment starting 2026-06-04.
Commitment baseCommitment({
  Pace pace = const DailyPace(1),
  int duration = 7,
  CommitmentStatus status = CommitmentStatus.active,
  String timeZone = 'UTC',
}) =>
    Commitment(
      id: 'old',
      attemptId: 'old',
      name: 'Yoga',
      path: HabitPath.build,
      description: '',
      duration: duration,
      startDate: '2026-06-04',
      pace: pace,
      reward: 'Coffee',
      status: status,
      timeZone: timeZone,
      createdAt: '2026-06-04T00:00:00Z',
    );

/// A snapshot with [c] and a successful check-in (count 1) on each of [days].
Snapshot snapshotWith(Commitment c, [List<String> days = const []]) => Snapshot(
      commitments: [c],
      checkIns: [
        for (final date in days)
          CheckIn(
            attemptId: c.attemptId,
            date: date,
            count: 1,
            updatedAt: at(date).toIso8601String(),
          ),
      ],
    );

/// A [KeyValueStore] whose writes can be made to fail, to test that failed
/// saves never report success.
class FlakyStore extends MemoryStore {
  /// When true, [setString] throws.
  bool failWrites = false;

  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    await super.setString(key, value);
  }
}
