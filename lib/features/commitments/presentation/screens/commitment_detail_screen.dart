/// One attempt in detail: timeline, calendar, reward, history, and the
/// lifecycle button (Pause / Resume / Restart).
library;

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../widgets/calendar_view.dart';
import '../widgets/log_modal.dart';
import '../widgets/status_chip.dart';
import '../widgets/timeline_view.dart';

/// Detail screen for `/commitment/:id`.
///
/// [requestedDate] (query `?date=`) preselects a day (used when opening from a
/// reminder). [justLocked] (`?locked=1`) plays the lock-settle animation.
class CommitmentDetailScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CommitmentDetailScreen({
    super.key,
    required this.id,
    this.requestedDate,
    this.justLocked = false,
  });

  /// Commitment id from the route.
  final String id;

  /// Optional preselected day.
  final String? requestedDate;

  /// True right after the wizard locked the commitment.
  final bool justLocked;

  @override
  ConsumerState<CommitmentDetailScreen> createState() => _CommitmentDetailScreenState();
}

class _CommitmentDetailScreenState extends ConsumerState<CommitmentDetailScreen> {
  String? _selectedDate;
  bool _busy = false;
  String _actionError = '';

  @override
  void initState() {
    super.initState();
    final d = widget.requestedDate;
    _selectedDate = d != null && isValidDate(d) ? d : null;
  }

  Future<void> _action(Commitment c, {required bool pause, VoidCallback? onDone}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = '';
    });
    try {
      final controller = ref.read(commitmentsProvider.notifier);
      await (pause ? controller.pause(c) : controller.resume(c));
      onDone?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _actionError =
            e is LockInException ? e.message : 'Could not save this change. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPause(Commitment c) async {
    _actionError = '';
    await showAppModal<void>(
      context,
      builder: (_) => _PauseModal(commitment: c, onConfirm: () => _pauseFromModal(c)),
    );
  }

  /// Runs the pause and reports an error message (or null) to the dialog.
  Future<String?> _pauseFromModal(Commitment c) async {
    try {
      await ref.read(commitmentsProvider.notifier).pause(c);
      return null;
    } catch (e) {
      return e is LockInException ? e.message : 'Could not save this change. Please retry.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final c = data.snapshot.commitments.where((x) => x.id == widget.id).firstOrNull;

    if (data.loading) {
      return const AppScreen(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Center(child: CircularProgressIndicator(color: AppColors.inkPrimary))],
      );
    }
    if (c == null) {
      return AppScreen(
        header: AppHeader(back: true, onBack: () => context.go('/')),
        mainAxisAlignment: MainAxisAlignment.center,
        gap: 20,
        children: [
          const Label('This commitment could not be found.'),
          LockButton(title: 'BACK TO FOCUS', onPressed: () => context.go('/')),
        ],
      );
    }

    final today = dateInZone(data.now, c.timeZone);
    final date = _selectedDate ?? today;
    final log = getLog(data.snapshot.checkIns, c, date);
    final writable = canApiCheckIn(c, date, data.now);
    final streakInfo = streak(c, data.snapshot.checkIns, data.now);
    final paused = c.status == CommitmentStatus.paused;

    String dayStatus() {
      if (isPausedDate(c, date)) return 'Paused date — no check-in due.';
      if (c.failureDate == date || log?.outcome == CheckInOutcome.missed) {
        return 'Missed outcome recorded.';
      }
      if (!isScheduled(c, date)) return 'No check-in scheduled.';
      if (log != null) return '${log.count} / ${targetForDate(c)} recorded.';
      if (date.compareTo(today) > 0) return 'Your promise is ahead of you.';
      return 'No progress recorded.';
    }

    return AppScreen(
      header: const AppHeader(back: true, label: 'Back To Dashboard'),
      gap: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (data.error != null)
          Notice(data.error!, onRetry: () => ref.read(commitmentsProvider.notifier).refresh()),
        LockSettle(
          enabled: widget.justLocked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(child: ScreenTitle(c.name, size: 38)),
                  StatusChip(c.status),
                ],
              ),
              if (c.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Label(c.description, size: 13, muted: true),
                ),
            ],
          ),
        ),
        // ---- Timeline ------------------------------------------------------
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const SectionLabel('Timeline'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.inkFocus,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Label(paceLabel(c.pace), size: 12, color: AppColors.onDark),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Label('Start Date', size: 11, muted: true),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Label(formatDate(c.startDate), size: 12),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Label(paused ? 'Original end' : 'End Date', size: 11, muted: true),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Label(
                                formatDate(
                                  paused
                                      ? computeEndDate(c.startDate, c.duration, const [])
                                      : endDate(c),
                                ),
                                size: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TimelineView(commitment: c, now: data.now),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Label(
                      'Current streak: ${streakInfo.count} ${streakInfo.unit}',
                      size: 11,
                      muted: true,
                    ),
                  ),
                  if (paused)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Label(
                        'Deadline extends on resume. Today’s target and earlier catch-up dates still count.',
                        size: 11,
                        muted: true,
                      ),
                    ),
                  if (c.status == CommitmentStatus.active && today.compareTo(endDate(c)) > 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Label(
                        'Awaiting final check-in. Your reward stays locked until every requirement is met.',
                        size: 12,
                      ),
                    ),
                  if (c.status == CommitmentStatus.broken)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Label(
                        '${switch (c.failureReason) {
                          FailureReason.quota => 'The weekly quota was not met.',
                          FailureReason.explicit => 'You recorded a missed day.',
                          _ => 'A check-in window expired.',
                        }} Your progress is preserved.',
                        size: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        // ---- Recent history ----------------------------------------------------
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const SectionLabel('Recent History'),
            CalendarView(
              selected: date,
              commitment: c,
              logs: data.snapshot.checkIns,
              onSelect: (d) => setState(() => _selectedDate = d),
            ),
            const Label(
              'Green: completed · Red: missed · Outline: paused · Dark: today',
              size: 11,
              muted: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Label(formatDate(date), size: 13, bold: true),
                  Label(dayStatus(), size: 12, muted: true),
                  if (writable)
                    LockButton(
                      light: true,
                      title: log != null ? 'UPDATE CHECK-IN' : 'LOG PROGRESS',
                      icon: Feather.checkSquare,
                      onPressed: () => showLogModal(context, LogSelection(c, date)),
                    ),
                ],
              ),
            ),
          ],
        ),
        // ---- Reward -----------------------------------------------------------
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const SectionLabel('Reward'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    spacing: 20,
                    children: [
                      StateMotion(
                        value: c.status,
                        settle: true,
                        child: AppIcon(
                          c.status == CommitmentStatus.completed ? Feather.award : Feather.gift,
                          size: 64,
                          color: c.status == CommitmentStatus.completed
                              ? AppColors.successForeground
                              : AppColors.inkPrimary,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Label(
                              c.status == CommitmentStatus.completed
                                  ? 'Reward unlocked'
                                  : 'Unlocks after day ${c.duration}',
                              size: 10,
                              muted: true,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Label(c.reward, size: 17, bold: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const AppDivider(),
                  Label(
                    c.status == CommitmentStatus.completed
                        ? 'You kept your promise. Enjoy the reward you chose.'
                        : 'Every single day brings you closer to the reward.',
                    size: 11,
                    muted: true,
                    align: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (c.reflection != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Your private reflection'),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Label(
                    c.reflection!.reason.isNotEmpty
                        ? c.reflection!.reason
                        : c.reflection!.note.isNotEmpty
                            ? c.reflection!.note
                            : 'You chose to start fresh without a note.',
                  ),
                ),
              ],
            ),
          ),
        if (c.events.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Attempt history'),
                for (final e in c.events)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Label('${e.type.name} · ${formatDate(e.date)}', size: 12, capitalize: true),
                  ),
              ],
            ),
          ),
        if (c.previousAttemptId != null)
          LockButton(
            light: true,
            title: 'VIEW PREVIOUS ATTEMPT',
            onPressed: () {
              final previous = data.snapshot.commitments
                  .where((x) => x.attemptId == c.previousAttemptId)
                  .firstOrNull;
              context.push('/commitment/${previous?.id ?? c.previousAttemptId}');
            },
          ),
        // ---- Lifecycle action ----------------------------------------------------
        if (c.restartedBy != null)
          LockButton(
            light: true,
            title: 'VIEW NEW ATTEMPT',
            onPressed: () => context.push('/commitment/${c.restartedBy}'),
          )
        else if (c.status == CommitmentStatus.broken)
          LockButton(
            light: true,
            title: 'Restart Commitment',
            icon: Feather.rotateCcw,
            onPressed: () => context.push('/commitment/${c.id}/reflect'),
          )
        else if (paused)
          LockButton(
            light: true,
            title: 'Resume Commitment',
            icon: Feather.play,
            loading: _busy,
            onPressed: () => _action(c, pause: false),
          )
        else if (canPause(c, data.now))
          LockButton(
            light: true,
            title: 'Pause Commitment',
            icon: Feather.pause,
            onPressed: () => _confirmPause(c),
          ),
        if (_actionError.isNotEmpty) ErrorNote(_actionError),
      ],
    );
  }
}

/// "Pause your commitment?" confirmation. [onConfirm] performs the pause and
/// returns an error message, or `null` on success.
class _PauseModal extends StatefulWidget {
  const _PauseModal({required this.commitment, required this.onConfirm});

  final Commitment commitment;
  final Future<String?> Function() onConfirm;

  @override
  State<_PauseModal> createState() => _PauseModalState();
}

class _PauseModalState extends State<_PauseModal> {
  bool _busy = false;
  String _error = '';

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final error = await widget.onConfirm();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ModalCard(
        title: 'Pause your commitment?',
        busy: _busy,
        children: [
          const Label(
            'Pause from tomorrow; today’s target still counts. Earlier check-ins keep their '
            'catch-up deadlines. Reminders stop now, and your deadline extends by paused days '
            'when you resume.',
          ),
          if (_error.isNotEmpty) ErrorNote(_error),
          LockButton(title: 'CONFIRM PAUSE', onPressed: _confirm, loading: _busy),
          LockButton(
            light: true,
            title: 'KEEP GOING',
            disabled: _busy,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
}
