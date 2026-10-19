/// The contract between the app and "wherever commitments are stored".
///
/// ## Why an interface?
///
/// Screens and controllers only ever talk to [CommitmentRepository]. Today the
/// implementation is [LocalCommitmentRepository] (data on the phone). When the
/// NestJS backend is ready you add a second class, e.g. `RemoteCommitmentRepository`,
/// that implements this same interface by calling your REST API, and change
/// **one line** in `providers.dart` to use it. No screen code changes.
///
/// This is the "repository pattern" and it is the main thing that keeps the
/// app scalable.
library;

import '../domain/models.dart';

/// Reads and writes commitments and check-ins.
///
/// Every method that changes data either fully succeeds or throws (and then
/// nothing was saved). Error messages thrown as [LockInException] are safe to
/// show to the user.
abstract interface class CommitmentRepository {
  /// Loads everything, after applying time-based expiry/completion rules.
  Future<Snapshot> load();

  /// Locks a validated [draft] into a new active commitment.
  ///
  /// [requestId] makes the call idempotent: sending the same id twice (for
  /// example after a network retry) returns the same commitment instead of
  /// creating a duplicate.
  Future<Commitment> create(Draft draft, String requestId);

  /// Saves the absolute [count] for [date] (see [CheckIn]).
  Future<void> log(Commitment commitment, String date, int count);

  /// Pauses [commitment] from tomorrow.
  Future<void> pause(Commitment commitment);

  /// Resumes a paused [commitment].
  Future<void> resume(Commitment commitment);

  /// Records an explicit missed day for [date].
  Future<void> fail(Commitment commitment, String date);

  /// Restarts a broken [commitment] as a new linked attempt, saving the
  /// optional reflection. Idempotent per [requestId] / attempt.
  Future<Commitment> restart(
    Commitment commitment,
    String requestId,
    String reason,
    String note,
  );
}
