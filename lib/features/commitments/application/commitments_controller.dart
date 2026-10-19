/// Holds the commitments for the signed-in user and exposes the actions
/// (create, log, pause, ...) that screens call.
///
/// ## Data flow
///
/// ```text
///  Screen ──calls──▶ CommitmentsController ──calls──▶ CommitmentRepository
///    ▲                      │                                │
///    └────── watches ───────┘                                ▼
///         CommitmentsState                       (device storage today,
///      (snapshot, loading, error, now)            NestJS API tomorrow)
/// ```
///
/// Screens never mutate data themselves; they call a method here, which asks
/// the repository to do the work, then reloads the state. The reload also
/// applies the time-based rules (expiry, completion).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/reduced_motion.dart';
import '../../../core/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../auth/application/session_controller.dart';
import '../data/commitment_repository.dart';
import '../data/remote_commitment_repository.dart';
import '../domain/models.dart';

/// The signed-in user's server-side commitments. The API enforces ownership
/// from the Clerk bearer token, so no client-side account key is sent.
final commitmentRepositoryProvider = Provider<CommitmentRepository>((ref) {
  final identity = ref.watch(sessionProvider.select((s) => s.identity));
  if (identity == null) {
    throw StateError('Commitments were requested while signed out.');
  }
  return RemoteCommitmentRepository(
    api: ref.watch(apiClientProvider),
    auth: () => ref.read(authGatewayProvider.future),
  );
});

/// Everything a screen needs to render commitments.
class CommitmentsState {
  /// Creates a state.
  const CommitmentsState({
    this.snapshot = Snapshot.empty,
    this.loading = true,
    this.refreshing = false,
    this.error,
    required this.now,
  });

  /// All attempts and check-ins.
  final Snapshot snapshot;

  /// True until the first load completes.
  final bool loading;

  /// True while a background refresh runs.
  final bool refreshing;

  /// A user-facing load error, if the last refresh failed.
  final String? error;

  /// The time of the last successful load. Widgets use this instead of reading
  /// the clock themselves, so a whole screen agrees on what "today" is.
  final DateTime now;

  /// Returns a copy with the given fields replaced. Pass `clearError: true` to
  /// remove the error.
  CommitmentsState copyWith({
    Snapshot? snapshot,
    bool? loading,
    bool? refreshing,
    String? error,
    bool clearError = false,
    DateTime? now,
  }) => CommitmentsState(
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: clearError ? null : (error ?? this.error),
    now: now ?? this.now,
  );
}

/// Loads commitments and performs actions on them.
class CommitmentsController extends Notifier<CommitmentsState> {
  late CommitmentRepository _repository;
  int _revision = 0; // guards against an older load finishing after a newer one
  Snapshot? _previous;

  @override
  CommitmentsState build() {
    _repository = ref.watch(commitmentRepositoryProvider);
    final clock = ref.watch(clockProvider);

    // Refresh every 30 s while the app is in the foreground, and immediately
    // when it comes back from the background. This is how an attempt that
    // expired while the app was closed gets noticed.
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(appLifecycleProvider) == AppLifecycleState.resumed) {
        unawaited(refresh());
      }
    });
    ref.onDispose(timer.cancel);
    ref.listen(appLifecycleProvider, (_, next) {
      if (next == AppLifecycleState.resumed) unawaited(refresh());
    });

    unawaited(Future<void>.microtask(refresh));
    return CommitmentsState(now: clock());
  }

  /// Reloads from the repository.
  Future<void> refresh() async {
    final current = ++_revision;
    state = state.copyWith(refreshing: true);
    try {
      final data = await _repository.load();
      if (!ref.mounted || current != _revision) return;
      _celebrateNewCompletions(data);
      _previous = data;
      state = state.copyWith(
        snapshot: data,
        clearError: true,
        now: ref.read(clockProvider)(),
      );
    } catch (_) {
      if (ref.mounted && current == _revision) {
        state = state.copyWith(
          error:
              'Could not refresh your commitments. Your last saved data is shown.',
        );
      }
    } finally {
      if (ref.mounted && current == _revision) {
        state = state.copyWith(loading: false, refreshing: false);
      }
    }
  }

  /// A success buzz when a refresh discovers an attempt just completed.
  void _celebrateNewCompletions(Snapshot data) {
    final before = _previous;
    if (before == null) return;
    final newlyCompleted = data.commitments.any(
      (c) =>
          c.status == CommitmentStatus.completed &&
          before.commitments.any(
            (old) =>
                old.attemptId == c.attemptId &&
                old.status != CommitmentStatus.completed,
          ),
    );
    if (newlyCompleted) ref.read(hapticsProvider).success();
  }

  // ----- actions -------------------------------------------------------

  /// Locks a draft. Safe to retry with the same [requestId].
  Future<Commitment> create(Draft draft, String requestId) async {
    final result = await _repository.create(draft, requestId);
    ref.read(hapticsProvider).success();
    if (ref.mounted) {
      // Show it immediately; the reload below confirms.
      final has = state.snapshot.commitments.any((c) => c.id == result.id);
      if (!has) {
        state = state.copyWith(
          snapshot: state.snapshot.copyWith(
            commitments: [result, ...state.snapshot.commitments],
          ),
        );
      }
    }
    await refresh();
    return result;
  }

  /// Saves an absolute [count] for [date].
  Future<void> log(Commitment c, String date, int count) async {
    try {
      await _repository.log(c, date, count);
    } catch (_) {
      await refresh();
      rethrow;
    }
    final target = c.pace is DailyPace ? (c.pace as DailyPace).count : 1;
    if (count >= target) ref.read(hapticsProvider).success();
    await refresh();
  }

  Future<void> _transition(
    Future<void> Function() action, {
    bool warning = false,
  }) async {
    try {
      await action();
      final haptics = ref.read(hapticsProvider);
      warning ? haptics.warning() : haptics.selection();
    } finally {
      await refresh();
    }
  }

  /// Pauses [c] from tomorrow.
  Future<void> pause(Commitment c) => _transition(() => _repository.pause(c));

  /// Resumes [c].
  Future<void> resume(Commitment c) => _transition(() => _repository.resume(c));

  /// Records a missed day.
  Future<void> fail(Commitment c, String date) =>
      _transition(() => _repository.fail(c, date), warning: true);

  /// Restarts a broken attempt; returns the new attempt.
  Future<Commitment> restart(
    Commitment c,
    String requestId,
    String reason,
    String note,
  ) async {
    try {
      final next = await _repository.restart(c, requestId, reason, note);
      ref.read(hapticsProvider).success();
      return next;
    } finally {
      await refresh();
    }
  }
}

/// The signed-in user's commitments.
final commitmentsProvider =
    NotifierProvider<CommitmentsController, CommitmentsState>(
      CommitmentsController.new,
    );
