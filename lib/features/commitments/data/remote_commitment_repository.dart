/// REST-backed commitments repository for the deployed LockIn API.
library;

import '../../../core/network/api_client.dart';
import '../../../core/utils/calendar_date.dart';
import '../../auth/data/auth_gateway.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import 'commitment_repository.dart';

/// Loads and mutates the signed-in user's server-side commitments.
///
/// The public API deliberately only permits one check-in for *today*; the
/// legacy UI's catch-up/count semantics are rejected here instead of being
/// falsely shown as saved.
class RemoteCommitmentRepository implements CommitmentRepository {
  RemoteCommitmentRepository({required this._api, required this._auth});

  final ApiClient _api;
  final Future<AuthGateway> Function() _auth;

  @override
  Future<Snapshot> load() => _safe(() async {
    // `/me` both provisions the internal profile and gives us the chance to
    // mirror Clerk's display name once, just as the web client does.
    final profile = _jsonObject(await _api.get('/me'));
    final gateway = await _auth();
    final name = gateway.currentUser?.name.trim() ?? '';
    if (profile['displayName'] == null && name.isNotEmpty) {
      await _api.patch(
        '/me',
        data: {'displayName': name.length > 80 ? name.substring(0, 80) : name},
      );
    }

    final body = await _api.get('/commitments');
    final records = _jsonList(body);
    final commitments = records.map(_commitmentFromApi).toList();
    final checkIns = <CheckIn>[
      for (final record in records)
        for (final checkIn in _jsonList(record['checkIns']))
          _checkInFromApi(checkIn, record['id'] as String),
    ];
    return Snapshot(commitments: commitments, checkIns: checkIns);
  });

  @override
  Future<Commitment> create(Draft draft, String requestId) => _safe(() async {
    final issue = validateDraft(draft);
    if (issue != null) throw LockInException(issue);
    if (draft.path == HabitPath.quit && draft.pace is! DailyPace) {
      throw const LockInException(
        'Quit commitments must use the everyday pace.',
      );
    }
    if (draft.pace case DailyPace(:final count) when count != 1) {
      throw const LockInException(
        'The LockIn API supports one daily check-in per commitment.',
      );
    }
    final payload = _createPayload(draft, startDate: draft.startDate);
    final data = _jsonObject(await _api.post('/commitments', data: payload));
    return _commitmentFromApi(data);
  });

  @override
  Future<void> log(Commitment commitment, String date, int count) =>
      _safe(() async {
        _requireToday(commitment, date);
        if (count < 1) {
          throw const LockInException(
            'Use the broken outcome only when you broke a quit commitment.',
          );
        }
        await _api.post(
          '/commitments/${commitment.id}/check-ins',
          data: const {'outcome': 'KEPT'},
        );
      });

  @override
  Future<void> fail(Commitment commitment, String date) => _safe(() async {
    _requireToday(commitment, date);
    if (commitment.path != HabitPath.quit) {
      throw const LockInException(
        'Build commitments can only be checked in as kept.',
      );
    }
    await _api.post(
      '/commitments/${commitment.id}/check-ins',
      data: const {'outcome': 'BROKEN', 'reason': 'Marked as broken in LockIn'},
    );
  });

  @override
  Future<void> pause(Commitment commitment) => _safe(() async {
    await _api.post('/commitments/${commitment.id}/pause');
  });

  @override
  Future<void> resume(Commitment commitment) => _safe(() async {
    await _api.post('/commitments/${commitment.id}/resume');
  });

  @override
  Future<Commitment> restart(
    Commitment commitment,
    String requestId,
    String reason,
    String note,
  ) => _safe(() async {
    if (commitment.status != CommitmentStatus.broken) {
      throw const LockInException('Only a broken commitment can be restarted.');
    }
    // The deployed API has no restart endpoint or attempt links. Starting a
    // fresh server-side commitment is the truthful equivalent.
    final payload = _createPayload(
      Draft(
        path: commitment.path,
        name: commitment.name,
        description: commitment.description,
        startDate: dateInZone(DateTime.now(), commitment.timeZone),
        duration: commitment.duration,
        pace: commitment.pace,
        reward: commitment.reward,
      ),
      startDate: dateInZone(DateTime.now(), commitment.timeZone),
      timeZone: commitment.timeZone,
    );
    final data = _jsonObject(await _api.post('/commitments', data: payload));
    return _commitmentFromApi(data);
  });

  Future<T> _safe<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ApiException catch (error) {
      throw LockInException(error.message);
    }
  }

  void _requireToday(Commitment commitment, String date) {
    final today = dateInZone(DateTime.now(), commitment.timeZone);
    if (date != today) {
      throw const LockInException('LockIn only accepts a check-in for today.');
    }
  }

  Map<String, dynamic> _createPayload(
    Draft draft, {
    required String startDate,
    String? timeZone,
  }) {
    final zone = timeZone ?? deviceZone();
    final pace = draft.pace;
    final payload = <String, dynamic>{
      'title': draft.name.trim(),
      'kind': draft.path == HabitPath.quit ? 'QUIT' : 'BUILD',
      'startDate': startDate,
      'endDate': addDays(startDate, draft.duration - 1),
      'timeZone': zone,
      'reward': draft.reward.trim(),
    };
    if (draft.description.trim().isNotEmpty) {
      payload['description'] = draft.description.trim();
    }

    switch (pace) {
      case DailyPace():
        payload.addAll({'ruleFrequency': 'DAILY', 'targetCount': 1});
      case WeeklyPace(:final count):
        payload.addAll({'ruleFrequency': 'WEEKLY', 'targetCount': count});
      case CustomPace(:final days):
        final scheduled = days.map((day) => day + 1).toList()..sort();
        payload.addAll({
          'ruleFrequency': 'WEEKLY',
          'targetCount': scheduled.length,
          'scheduledDays': scheduled,
        });
      case MonthlyPace(:final count):
        payload.addAll({'ruleFrequency': 'MONTHLY', 'targetCount': count});
      case WindowPace(:final targetCount, :final windowDays):
        payload.addAll({
          'ruleFrequency': 'WINDOW',
          'targetCount': targetCount,
          'windowDays': windowDays,
        });
    }
    return payload;
  }

  Commitment _commitmentFromApi(Map<String, dynamic> json) {
    final startDate = _dateOnly(json['startDate']);
    final endDate = _dateOnly(json['endDate']);
    final status = switch (json['status']) {
      'PAUSED' => CommitmentStatus.paused,
      'COMPLETED' => CommitmentStatus.completed,
      'BROKEN' => CommitmentStatus.broken,
      _ => CommitmentStatus.active,
    };
    final pausedAt = json['pausedAt'] as String?;
    final brokenAt = json['brokenAt'] as String?;
    final completedAt = json['completedAt'] as String?;
    return Commitment(
      id: json['id'] as String,
      attemptId: json['id'] as String,
      path: json['kind'] == 'QUIT' ? HabitPath.quit : HabitPath.build,
      name: json['title'] as String,
      description: json['description'] as String? ?? '',
      startDate: startDate,
      duration: dayDifference(startDate, endDate) + 1,
      pace: _paceFromApi(json),
      reward: json['reward'] as String,
      timeZone: json['timeZone'] as String,
      status: status,
      createdAt: json['createdAt'] as String,
      pauses: status == CommitmentStatus.paused && pausedAt != null
          ? [PauseInterval(start: _dateOnly(pausedAt))]
          : const [],
      failureDate: brokenAt == null ? null : _dateOnly(brokenAt),
      failureReason: status == CommitmentStatus.broken
          ? FailureReason.explicit
          : null,
      completedAt: completedAt,
      events: [
        LifecycleEvent(
          type: LifecycleEventType.locked,
          at: json['createdAt'] as String,
          date: startDate,
        ),
        if (pausedAt != null)
          LifecycleEvent(
            type: LifecycleEventType.paused,
            at: pausedAt,
            date: _dateOnly(pausedAt),
          ),
        if (brokenAt != null)
          LifecycleEvent(
            type: LifecycleEventType.broken,
            at: brokenAt,
            date: _dateOnly(brokenAt),
          ),
        if (completedAt != null)
          LifecycleEvent(
            type: LifecycleEventType.completed,
            at: completedAt,
            date: _dateOnly(completedAt),
          ),
      ],
    );
  }

  Pace _paceFromApi(Map<String, dynamic> json) {
    final target = json['targetCount'] as int;
    return switch (json['ruleFrequency']) {
      'DAILY' => const DailyPace(1),
      'MONTHLY' => MonthlyPace(target),
      'WINDOW' => WindowPace(target, json['windowDays'] as int),
      'WEEKLY' =>
        ((json['scheduledDays'] as List<dynamic>?) ?? const []).isNotEmpty
            ? CustomPace(
                ((json['scheduledDays'] as List<dynamic>).cast<int>())
                    .map((day) => day - 1)
                    .toList(),
              )
            : WeeklyPace(target),
      _ => const DailyPace(1),
    };
  }

  CheckIn _checkInFromApi(Map<String, dynamic> json, String commitmentId) =>
      CheckIn(
        attemptId: commitmentId,
        date: _dateOnly(json['date']),
        count: json['outcome'] == 'KEPT' ? 1 : 0,
        outcome: json['outcome'] == 'KEPT'
            ? CheckInOutcome.success
            : CheckInOutcome.missed,
        updatedAt: json['updatedAt'] as String,
      );

  String _dateOnly(Object? value) {
    final text = value as String;
    if (text.length < 10) {
      throw const FormatException('API returned an invalid calendar date.');
    }
    return text.substring(0, 10);
  }

  Map<String, dynamic> _jsonObject(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  List<Map<String, dynamic>> _jsonList(dynamic value) =>
      (value as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
}
