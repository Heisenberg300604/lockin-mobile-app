/// REST-backed commitments repository for the deployed LockIn API.
library;

import '../../../core/network/api_client.dart';
import '../../../core/utils/calendar_date.dart';
import '../../auth/data/auth_gateway.dart';
import '../domain/api_progress.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import 'commitment_repository.dart';

/// Loads and mutates the signed-in user's server-side commitments.
///
/// The API records one kept/broken result per date: today, or a kept day
/// backfilled within the previous [apiBackfillDays] days. The legacy UI's
/// count-based semantics are rejected here instead of being falsely shown as
/// saved.
class RemoteCommitmentRepository implements CommitmentRepository {
  RemoteCommitmentRepository({required this._api, required this._auth});

  final ApiClient _api;
  final Future<AuthGateway> Function() _auth;

  @override
  Future<Snapshot> load() => _safe(() async {
    // `/me` both provisions the internal profile and gives us the chance to
    // mirror Clerk's display name once, just as the web client does.
    final profile = _jsonObject(await _api.get('/me'));
    var displayName = (profile['displayName'] as String?)?.trim();
    if (displayName == null || displayName.isEmpty) {
      final gateway = await _auth();
      final name = gateway.currentUser?.name.trim() ?? '';
      if (name.isNotEmpty) {
        final saved = _jsonObject(
          await _api.patch(
            '/me',
            data: {
              'displayName': name.length > 80 ? name.substring(0, 80) : name,
            },
          ),
        );
        displayName = (saved['displayName'] as String?)?.trim();
      }
    }

    final body = await _api.get('/commitments');
    final records = _jsonList(body);
    final commitments = records.map(_commitmentFromApi).toList();
    final checkIns = <CheckIn>[
      for (final record in records)
        for (final checkIn in _jsonList(
          record['checkIns'] ?? const <dynamic>[],
        ))
          _checkInFromApi(checkIn, record['id'] as String),
    ];
    return Snapshot(
      commitments: commitments,
      checkIns: checkIns,
      displayName: displayName == null || displayName.isEmpty
          ? null
          : displayName,
    );
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
    final feasibility = apiFeasibilityError(
      startDate: draft.startDate,
      duration: draft.duration,
      pace: draft.pace,
    );
    if (feasibility != null) throw LockInException(feasibility);
    final payload = _createPayload(draft, startDate: draft.startDate);
    final data = _jsonObject(await _api.post('/commitments', data: payload));
    return _commitmentFromApi(data);
  });

  @override
  Future<void> log(Commitment commitment, String date, int count) =>
      _safe(() async {
        final today = _requireLoggable(commitment, date);
        if (count < 1) {
          throw const LockInException(
            'Use the broken outcome only when you broke a quit commitment.',
          );
        }
        await _api.post(
          '/commitments/${commitment.id}/check-ins',
          // Today is left to the server's own clock, exactly as the web app
          // does; only backfilled days name their date.
          data: {'outcome': 'KEPT', if (date != today) 'date': date},
        );
      });

  @override
  Future<void> fail(
    Commitment commitment,
    String date, {
    String reason = '',
    String note = '',
  }) => _safe(() async {
    final today = _requireLoggable(commitment, date);
    if (commitment.path != HabitPath.quit) {
      throw const LockInException(
        'Build commitments can only be checked in as kept.',
      );
    }
    final why = reason.trim();
    final detail = note.trim();
    await _api.post(
      '/commitments/${commitment.id}/check-ins',
      data: {
        'outcome': 'BROKEN',
        if (date != today) 'date': date,
        'reason': why.isEmpty ? 'Commitment broken.' : _limit(why, 240),
        if (detail.isNotEmpty) 'note': _limit(detail, 1000),
      },
    );
  });

  @override
  Future<Commitment> updateReward(Commitment commitment, String reward) =>
      _safe(() async {
        final value = reward.trim();
        if (value.isEmpty) {
          throw const LockInException('Add a reward before saving.');
        }
        if (value.length > maxRewardLength) {
          throw const LockInException(
            'Keep the reward within $maxRewardLength characters.',
          );
        }
        final data = _jsonObject(
          await _api.patch(
            '/commitments/${commitment.id}',
            data: {'reward': value},
          ),
        );
        return _commitmentFromApi(data);
      });

  @override
  Future<void> delete(Commitment commitment) => _safe(() async {
    await _api.delete('/commitments/${commitment.id}');
  });

  @override
  Future<void> updateDisplayName(String displayName) => _safe(() async {
    final value = displayName.trim();
    if (value.isEmpty || value.length > 80) {
      throw const LockInException(
        'Use a display name between 1 and 80 characters.',
      );
    }
    await _api.patch('/me', data: {'displayName': value});
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

  /// Rejects dates the server would refuse (future, or older than the
  /// backfill window) and returns today in the commitment's zone.
  String _requireLoggable(Commitment commitment, String date) {
    final today = dateInZone(DateTime.now(), commitment.timeZone);
    if (date.compareTo(today) > 0) {
      throw const LockInException('Future dates cannot be logged.');
    }
    if (dayDifference(date, today) > apiBackfillDays) {
      throw const LockInException(
        'Check-ins may only be backfilled for the previous two days.',
      );
    }
    return today;
  }

  String _limit(String value, int max) =>
      value.length > max ? value.substring(0, max) : value;

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
      breakReason: (json['breakReason'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['breakReason'] as String).trim(),
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
        updatedAt:
            json['updatedAt'] as String? ?? json['createdAt'] as String? ?? '',
        createdAt: json['createdAt'] as String?,
        note: json['note'] as String?,
        reason: json['reason'] as String?,
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
