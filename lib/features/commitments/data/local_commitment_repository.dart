/// Stores commitments on the device, as one JSON document.
///
/// This is a port of the React Native app's "local repository". It is used
/// until the backend APIs exist (see [CommitmentRepository]).
///
/// ## How a write works
///
/// 1. **Queue.** All operations run one after another (`_queue`). Two quick
///    taps can therefore never interleave and corrupt each other.
/// 2. **Read** the stored snapshot.
/// 3. **Reconcile** time-based rules (expiry/completion) and save if they
///    changed anything, *before* the requested action. This matters: if the
///    attempt expired while the app was closed, the action must be judged
///    against the real, expired state.
/// 4. **Apply** the action (a pure function from `lifecycle.dart`).
/// 5. **Reconcile again** (the action itself may complete or break something).
/// 6. **Save** only if the data changed. If saving throws, the whole operation
///    fails, so the UI never claims success for something that was not stored.
library;

import 'dart:async';
import 'dart:convert';

import '../../../core/utils/calendar_date.dart';
import '../domain/lifecycle.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import 'commitment_repository.dart';
import 'key_value_store.dart';

/// Device-local implementation of [CommitmentRepository].
class LocalCommitmentRepository implements CommitmentRepository {
  /// Creates a repository.
  ///
  /// [storageKey] separates users (e.g. `lockin.data.v1.user_123`). [clock]
  /// can be replaced in tests to control "now".
  LocalCommitmentRepository({
    required KeyValueStore store,
    required String storageKey,
    DateTime Function()? clock,
  })  : _store = store, // ignore: prefer_initializing_formals
        _key = storageKey,
        _now = clock ?? DateTime.now;

  final KeyValueStore _store;
  final String _key;
  final DateTime Function() _now;

  Future<void> _queue = Future<void>.value();

  Future<Snapshot> _read() async {
    final raw = await _store.getString(_key);
    if (raw == null) return Snapshot.empty;
    return Snapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _write(Snapshot data) => _store.setString(_key, jsonEncode(data.toJson()));

  /// Runs [action] inside the serialized read → reconcile → apply → save cycle.
  Future<T> _change<T>(({Snapshot data, T result}) Function(Snapshot data) action) {
    final operation = _queue.then((_) async {
      var data = await _read();

      // Persist expiry even if the requested action turns out to be invalid.
      final reconciled = reconcile(data, _now());
      if (!identical(reconciled, data)) {
        data = reconciled;
        await _write(data);
      }

      final before = jsonEncode(data.toJson());
      final applied = action(data);
      final after = reconcile(applied.data, _now());
      if (jsonEncode(after.toJson()) != before) await _write(after);
      return applied.result;
    });
    // A failed operation must not block the next one.
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Commitment _find(Snapshot data, Commitment c) {
    for (final x in data.commitments) {
      if (x.attemptId == c.attemptId) return x;
    }
    throw const LockInException('This commitment is no longer available.');
  }

  Snapshot _replace(Snapshot data, Commitment updated) => data.copyWith(
        commitments: [
          for (final c in data.commitments) c.attemptId == updated.attemptId ? updated : c,
        ],
      );

  @override
  Future<Snapshot> load() => _change((data) => (data: data, result: data));

  @override
  Future<void> pause(Commitment commitment) => _change((data) {
        final paused = pauseCommitment(_find(data, commitment), _now());
        return (data: _replace(data, paused), result: null);
      });

  @override
  Future<void> resume(Commitment commitment) => _change((data) {
        final resumed = resumeCommitment(_find(data, commitment), _now());
        return (data: _replace(data, resumed), result: null);
      });

  @override
  Future<void> fail(Commitment commitment, String date) => _change((data) {
        final next = failDay(data, _find(data, commitment), date, _now());
        return (data: next, result: null);
      });

  @override
  Future<Commitment> restart(
    Commitment commitment,
    String requestId,
    String reason,
    String note,
  ) =>
      _change((data) {
        final restarted = restartAttempt(
          data,
          _find(data, commitment),
          requestId,
          reason,
          note,
          _now(),
        );
        return (data: restarted.snapshot, result: restarted.attempt);
      });

  @override
  Future<Commitment> create(Draft draft, String requestId) => _change((data) {
        // Idempotent: a retry with the same id returns the stored commitment.
        for (final c in data.commitments) {
          if (c.id == requestId) return (data: data, result: c);
        }
        final problem = validateDraft(draft, _now());
        if (problem != null) throw LockInException(problem);

        final now = _now();
        final created = withEvent(
          Commitment(
            id: requestId,
            attemptId: requestId,
            path: draft.path!,
            name: draft.name.trim(),
            description: draft.description.trim(),
            startDate: draft.startDate,
            duration: draft.duration,
            pace: draft.pace,
            reward: draft.reward.trim(),
            timeZone: deviceZone(),
            status: CommitmentStatus.active,
            createdAt: now.toUtc().toIso8601String(),
          ),
          LifecycleEventType.locked,
          now,
          draft.startDate,
        );
        return (
          data: data.copyWith(commitments: [created, ...data.commitments]),
          result: created,
        );
      });

  @override
  Future<void> log(Commitment commitment, String date, int count) => _change((data) {
        final current = _find(data, commitment);
        final now = _now();
        validateCheckIn(current, date, count, now);

        final target = current.pace is DailyPace ? (current.pace as DailyPace).count : 1;
        final entry = CheckIn(
          attemptId: commitment.attemptId,
          date: date,
          count: count,
          outcome: count >= target ? CheckInOutcome.success : CheckInOutcome.partial,
          updatedAt: now.toUtc().toIso8601String(),
        );
        final checkIns = [...data.checkIns];
        final i = checkIns.indexWhere(
          (l) => l.attemptId == commitment.attemptId && l.date == date,
        );
        if (i < 0) {
          checkIns.add(entry);
        } else {
          checkIns[i] = entry;
        }
        return (data: data.copyWith(checkIns: checkIns), result: null);
      });
}
