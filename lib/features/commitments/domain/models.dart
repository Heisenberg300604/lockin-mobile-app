/// The data types of the app (the "vocabulary" every other file speaks).
///
/// Nothing in here knows about Flutter, storage, or the network. That is on
/// purpose: these are plain Dart objects so the business rules that use them
/// can be unit-tested in milliseconds and reused unchanged when a real backend
/// replaces on-device storage.
///
/// ## Glossary
///
/// * **Commitment / attempt** – one run at a habit. When an attempt is broken
///   and the user restarts, a *new* attempt is created and linked to the old
///   one. The old one is never edited, so history stays truthful. In this
///   codebase one [Commitment] object *is* one attempt (it has an `attemptId`).
/// * **Check-in** ([CheckIn]) – the user's recorded result for one calendar day.
/// * **Pace** ([Pace]) – how often the habit is due.
///
/// ## Immutability
///
/// All classes are immutable. To "change" one you call `copyWith`, which
/// returns a new object. Immutable data makes state management predictable:
/// Riverpod can tell something changed simply because the object is different.
///
/// ## JSON
///
/// Every class has `toJson` / `fromJson`. The shape is identical to the React
/// Native app's stored data, so a backend can adopt it unchanged.
library;

/// Whether the user is building a good habit or quitting a bad one.
enum HabitPath { build, quit }

/// Where an attempt is in its life. See `docs/behavior-spec` in the original
/// repo, or [lifecycle.dart], for the allowed transitions.
enum CommitmentStatus { active, paused, broken, completed }

/// Why an attempt ended up broken.
enum FailureReason {
  /// A check-in window expired with the obligation unmet.
  missed,

  /// The user explicitly recorded a missed day.
  explicit,

  /// A weekly quota period ended below its required number of successes.
  quota,
}

/// Kinds of dated events in an attempt's history.
enum LifecycleEventType {
  locked,
  paused,
  resumed,
  broken,
  completed,
  restarted,
}

/// The result stored on a [CheckIn].
enum CheckInOutcome { success, missed, partial }

/// A failure to apply a business rule (invalid input, closed window, ...).
///
/// The [message] is written for end users and is shown directly in the UI, so
/// keep it friendly and free of technical jargon.
class LockInException implements Exception {
  /// Creates an exception with a user-facing [message].
  const LockInException(this.message);

  /// Friendly explanation, safe to display.
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Pace
// ---------------------------------------------------------------------------

/// How often a habit is due. Exactly one of three shapes:
///
/// * [DailyPace] – every day. `count` is how many repetitions per day
///   (`1` = "Everyday", `3` = "3 times a day").
/// * [WeeklyPace] – a quota: `count` successful *different days* in every
///   seven-day period ("3 days per week").
/// * [CustomPace] – only on chosen weekdays (Monday = 0 ... Sunday = 6).
///
/// `sealed` means the compiler knows these are the only three subtypes, so a
/// `switch` over a [Pace] must handle all of them; forgetting one is a compile
/// error rather than a runtime bug.
sealed class Pace {
  const Pace();

  /// Reads the stored JSON, e.g. `{"kind": "daily", "count": 1}`.
  factory Pace.fromJson(Map<String, dynamic> json) {
    switch (json['kind']) {
      case 'daily':
        return DailyPace(json['count'] as int);
      case 'weekly':
        return WeeklyPace(json['count'] as int);
      case 'custom':
        return CustomPace((json['days'] as List<dynamic>).cast<int>());
      case 'monthly':
        return MonthlyPace(json['count'] as int);
      case 'window':
        return WindowPace(json['count'] as int, json['windowDays'] as int);
      default:
        throw FormatException('Unknown pace kind: ${json['kind']}');
    }
  }

  /// JSON form of this pace.
  Map<String, dynamic> toJson();
}

/// Due every day, [count] times a day.
final class DailyPace extends Pace {
  /// Creates a daily pace.
  const DailyPace(this.count);

  /// Repetitions required per day (1 for a simple yes/no habit).
  final int count;

  @override
  Map<String, dynamic> toJson() => {'kind': 'daily', 'count': count};
}

/// Due [count] different days in every seven-day period.
final class WeeklyPace extends Pace {
  /// Creates a weekly quota.
  const WeeklyPace(this.count);

  /// Required successful days per period (1 to 7).
  final int count;

  @override
  Map<String, dynamic> toJson() => {'kind': 'weekly', 'count': count};
}

/// Due only on specific weekdays.
final class CustomPace extends Pace {
  /// Creates a custom-days pace.
  const CustomPace(this.days);

  /// Weekday numbers, Monday = 0 ... Sunday = 6.
  final List<int> days;

  @override
  Map<String, dynamic> toJson() => {'kind': 'custom', 'days': days};
}

/// A target number of kept days in each calendar month. This is received from
/// the deployed API; the current creation flow does not create it yet.
final class MonthlyPace extends Pace {
  const MonthlyPace(this.count);

  final int count;

  @override
  Map<String, dynamic> toJson() => {'kind': 'monthly', 'count': count};
}

/// A target number of kept days within consecutive windows from the start.
/// This is received from the deployed API; the current creation flow does not
/// create it yet.
final class WindowPace extends Pace {
  const WindowPace(this.targetCount, this.windowDays);

  final int targetCount;
  final int windowDays;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'window',
    'count': targetCount,
    'windowDays': windowDays,
  };
}

// ---------------------------------------------------------------------------
// Draft (the creation wizard's work-in-progress)
// ---------------------------------------------------------------------------

/// A commitment that is still being filled in by the six-step wizard.
///
/// Becomes a [Commitment] only after the user confirms and locks it.
class Draft {
  /// Creates a draft.
  const Draft({
    required this.path,
    required this.name,
    required this.description,
    required this.startDate,
    required this.duration,
    required this.pace,
    required this.reward,
  });

  /// Build or quit; `null` until the user picks one in step 1.
  final HabitPath? path;

  /// The target, e.g. "Daily Yoga Practice" (1-80 characters).
  final String name;

  /// Optional details (max 300 characters).
  final String description;

  /// First day, `yyyy-MM-dd`.
  final String startDate;

  /// Length of the challenge in calendar days (1-365), start day included.
  final int duration;

  /// How often the habit is due.
  final Pace pace;

  /// The self-chosen reward (max 120 characters).
  final String reward;

  /// Returns a copy with the given fields replaced.
  Draft copyWith({
    HabitPath? path,
    String? name,
    String? description,
    String? startDate,
    int? duration,
    Pace? pace,
    String? reward,
  }) => Draft(
    path: path ?? this.path,
    name: name ?? this.name,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    duration: duration ?? this.duration,
    pace: pace ?? this.pace,
    reward: reward ?? this.reward,
  );

  /// JSON form (used to persist an unfinished draft on the device).
  Map<String, dynamic> toJson() => {
    'path': path?.name,
    'name': name,
    'description': description,
    'startDate': startDate,
    'duration': duration,
    'pace': pace.toJson(),
    'reward': reward,
  };

  /// Reads a draft saved with [toJson].
  factory Draft.fromJson(Map<String, dynamic> json) => Draft(
    path: json['path'] == null
        ? null
        : HabitPath.values.byName(json['path'] as String),
    name: json['name'] as String,
    description: json['description'] as String,
    startDate: json['startDate'] as String,
    duration: json['duration'] as int,
    pace: Pace.fromJson(json['pace'] as Map<String, dynamic>),
    reward: json['reward'] as String,
  );
}

// ---------------------------------------------------------------------------
// Commitment (an attempt)
// ---------------------------------------------------------------------------

/// A pause interval. Dates from [start] up to (but not including) [end] are
/// "frozen": nothing is due and the challenge deadline moves out by that many
/// days. [end] is `null` while the attempt is still paused.
class PauseInterval {
  /// Creates a pause interval.
  const PauseInterval({required this.start, this.end});

  /// First frozen day.
  final String start;

  /// Day the attempt resumed (not frozen), or `null` while paused.
  final String? end;

  /// Returns a copy with [end] set.
  PauseInterval closedOn(String end) => PauseInterval(start: start, end: end);

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'start': start,
    if (end != null) 'end': end,
  };

  /// Reads a pause interval from JSON.
  factory PauseInterval.fromJson(Map<String, dynamic> json) => PauseInterval(
    start: json['start'] as String,
    end: json['end'] as String?,
  );
}

/// One dated entry in an attempt's timeline ("paused · Jun 6").
class LifecycleEvent {
  /// Creates an event.
  const LifecycleEvent({
    required this.type,
    required this.at,
    required this.date,
  });

  /// What happened.
  final LifecycleEventType type;

  /// The exact instant it was recorded (ISO-8601, UTC).
  final String at;

  /// The calendar day it belongs to (in the attempt's time zone).
  final String date;

  /// JSON form.
  Map<String, dynamic> toJson() => {'type': type.name, 'at': at, 'date': date};

  /// Reads an event from JSON.
  factory LifecycleEvent.fromJson(Map<String, dynamic> json) => LifecycleEvent(
    type: LifecycleEventType.values.byName(json['type'] as String),
    at: json['at'] as String,
    date: json['date'] as String,
  );
}

/// The private note a user can save when an attempt breaks.
class Reflection {
  /// Creates a reflection.
  const Reflection({
    required this.reason,
    required this.note,
    required this.savedAt,
  });

  /// One of the preset reasons ("Low Energy", ...) or empty.
  final String reason;

  /// Free-text note (max 500 characters) or empty.
  final String note;

  /// ISO-8601 instant it was saved.
  final String savedAt;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'reason': reason,
    'note': note,
    'savedAt': savedAt,
  };

  /// Reads a reflection from JSON.
  factory Reflection.fromJson(Map<String, dynamic> json) => Reflection(
    reason: json['reason'] as String,
    note: json['note'] as String,
    savedAt: json['savedAt'] as String,
  );
}

/// One attempt at a habit: its fixed rules plus everything that has happened.
///
/// The *rules* (`path`, `name`, `duration`, `pace`, `reward`, `timeZone`) are
/// frozen the moment the commitment is locked. Only the lifecycle fields
/// (`status`, `pauses`, `events`, ...) ever change.
class Commitment {
  /// Creates a commitment.
  const Commitment({
    required this.id,
    required this.attemptId,
    required this.path,
    required this.name,
    required this.description,
    required this.startDate,
    required this.duration,
    required this.pace,
    required this.reward,
    required this.timeZone,
    required this.status,
    required this.createdAt,
    this.commitmentId,
    this.previousAttemptId,
    this.restartedBy,
    this.pauses = const [],
    this.failureDate,
    this.failureReason,
    this.completedAt,
    this.reflection,
    this.events = const [],
  });

  /// Unique id (also used in navigation routes).
  final String id;

  /// Id of this attempt. Equal to [id] today; kept separate because a backend
  /// may distinguish a commitment from its attempts.
  final String attemptId;

  /// Build or quit.
  final HabitPath path;

  /// The target name.
  final String name;

  /// Optional details.
  final String description;

  /// First day (`yyyy-MM-dd`) in [timeZone].
  final String startDate;

  /// Planned number of non-paused days, start day included.
  final int duration;

  /// How often it is due.
  final Pace pace;

  /// The self-chosen reward.
  final String reward;

  /// IANA zone fixed when locked. Travelling never changes this attempt's day
  /// boundaries.
  final String timeZone;

  /// Current lifecycle status.
  final CommitmentStatus status;

  /// ISO-8601 creation instant.
  final String createdAt;

  /// Id shared by every attempt of the same habit (first attempt's id).
  final String? commitmentId;

  /// The broken attempt this one replaced, if it is a restart.
  final String? previousAttemptId;

  /// The attempt that replaced this one, once restarted.
  final String? restartedBy;

  /// Every pause, oldest first.
  final List<PauseInterval> pauses;

  /// Day the attempt broke (the *missed* day, not the day it was detected).
  final String? failureDate;

  /// Why it broke.
  final FailureReason? failureReason;

  /// ISO-8601 instant it completed.
  final String? completedAt;

  /// Private reflection saved when restarting.
  final Reflection? reflection;

  /// Dated history.
  final List<LifecycleEvent> events;

  /// Returns a copy with the given fields replaced.
  ///
  /// Note: you cannot use this to set a field back to `null`. No rule in the
  /// app ever needs to; fields only get filled in over an attempt's life.
  Commitment copyWith({
    CommitmentStatus? status,
    List<PauseInterval>? pauses,
    String? failureDate,
    FailureReason? failureReason,
    String? completedAt,
    Reflection? reflection,
    String? restartedBy,
    List<LifecycleEvent>? events,
  }) => Commitment(
    id: id,
    attemptId: attemptId,
    path: path,
    name: name,
    description: description,
    startDate: startDate,
    duration: duration,
    pace: pace,
    reward: reward,
    timeZone: timeZone,
    status: status ?? this.status,
    createdAt: createdAt,
    commitmentId: commitmentId,
    previousAttemptId: previousAttemptId,
    restartedBy: restartedBy ?? this.restartedBy,
    pauses: pauses ?? this.pauses,
    failureDate: failureDate ?? this.failureDate,
    failureReason: failureReason ?? this.failureReason,
    completedAt: completedAt ?? this.completedAt,
    reflection: reflection ?? this.reflection,
    events: events ?? this.events,
  );

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'attemptId': attemptId,
    'path': path.name,
    'name': name,
    'description': description,
    'startDate': startDate,
    'duration': duration,
    'pace': pace.toJson(),
    'reward': reward,
    'timeZone': timeZone,
    'status': status.name,
    'createdAt': createdAt,
    if (commitmentId != null) 'commitmentId': commitmentId,
    if (previousAttemptId != null) 'previousAttemptId': previousAttemptId,
    if (restartedBy != null) 'restartedBy': restartedBy,
    'pauses': pauses.map((p) => p.toJson()).toList(),
    if (failureDate != null) 'failureDate': failureDate,
    if (failureReason != null) 'failureReason': failureReason!.name,
    if (completedAt != null) 'completedAt': completedAt,
    if (reflection != null) 'reflection': reflection!.toJson(),
    'events': events.map((e) => e.toJson()).toList(),
  };

  /// Reads a commitment from JSON.
  factory Commitment.fromJson(Map<String, dynamic> json) => Commitment(
    id: json['id'] as String,
    attemptId: json['attemptId'] as String,
    path: HabitPath.values.byName(json['path'] as String),
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    startDate: json['startDate'] as String,
    duration: json['duration'] as int,
    pace: Pace.fromJson(json['pace'] as Map<String, dynamic>),
    reward: json['reward'] as String,
    timeZone: json['timeZone'] as String,
    status: CommitmentStatus.values.byName(json['status'] as String),
    createdAt: json['createdAt'] as String,
    commitmentId: json['commitmentId'] as String?,
    previousAttemptId: json['previousAttemptId'] as String?,
    restartedBy: json['restartedBy'] as String?,
    pauses: ((json['pauses'] as List<dynamic>?) ?? const [])
        .map((p) => PauseInterval.fromJson(p as Map<String, dynamic>))
        .toList(),
    failureDate: json['failureDate'] as String?,
    failureReason: json['failureReason'] == null
        ? null
        : FailureReason.values.byName(json['failureReason'] as String),
    completedAt: json['completedAt'] as String?,
    reflection: json['reflection'] == null
        ? null
        : Reflection.fromJson(json['reflection'] as Map<String, dynamic>),
    events: ((json['events'] as List<dynamic>?) ?? const [])
        .map((e) => LifecycleEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// Check-ins and the snapshot
// ---------------------------------------------------------------------------

/// The recorded result for one attempt on one calendar day.
///
/// There is at most one per (attempt, date); saving again *replaces* it with
/// an absolute [count]. That is what makes retries safe: re-sending "3 of 10"
/// can never turn into "6 of 10".
class CheckIn {
  /// Creates a check-in.
  const CheckIn({
    required this.attemptId,
    required this.date,
    required this.count,
    required this.updatedAt,
    this.outcome,
  });

  /// The attempt this belongs to.
  final String attemptId;

  /// The calendar day it is for (not the day it was saved: catch-up entries
  /// belong to the original day).
  final String date;

  /// Absolute number of repetitions done.
  final int count;

  /// ISO-8601 instant of the last save.
  final String updatedAt;

  /// Success, partial progress, or an explicit "missed".
  final CheckInOutcome? outcome;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'attemptId': attemptId,
    'date': date,
    'count': count,
    'updatedAt': updatedAt,
    if (outcome != null) 'outcome': outcome!.name,
  };

  /// Reads a check-in from JSON.
  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
    attemptId: json['attemptId'] as String,
    date: json['date'] as String,
    count: json['count'] as int,
    updatedAt: json['updatedAt'] as String,
    outcome: json['outcome'] == null
        ? null
        : CheckInOutcome.values.byName(json['outcome'] as String),
  );
}

/// Everything the app knows: all attempts plus all check-ins.
///
/// The whole snapshot is read and written as one unit, which is what lets the
/// lifecycle rules apply several related changes atomically.
class Snapshot {
  /// Creates a snapshot.
  const Snapshot({this.commitments = const [], this.checkIns = const []});

  /// An empty account.
  static const Snapshot empty = Snapshot();

  /// All attempts, newest first.
  final List<Commitment> commitments;

  /// All check-ins.
  final List<CheckIn> checkIns;

  /// Returns a copy with the given lists replaced.
  Snapshot copyWith({List<Commitment>? commitments, List<CheckIn>? checkIns}) =>
      Snapshot(
        commitments: commitments ?? this.commitments,
        checkIns: checkIns ?? this.checkIns,
      );

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'commitments': commitments.map((c) => c.toJson()).toList(),
    'checkIns': checkIns.map((c) => c.toJson()).toList(),
  };

  /// Reads a snapshot from JSON.
  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
    commitments: ((json['commitments'] as List<dynamic>?) ?? const [])
        .map((c) => Commitment.fromJson(c as Map<String, dynamic>))
        .toList(),
    checkIns: ((json['checkIns'] as List<dynamic>?) ?? const [])
        .map((c) => CheckIn.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}
