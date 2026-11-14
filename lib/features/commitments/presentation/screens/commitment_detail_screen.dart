/// One commitment in detail, matching the LockIn web app: timeline, check-in
/// calendar (with two-day backfill), today's check-in, reward (editable while
/// active), commitment details, and lifecycle actions (pause / resume /
/// restart / delete).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_field.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/lock_loader.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/validation.dart';
import '../widgets/check_in_calendar.dart';
import '../widgets/log_modal.dart';
import '../widgets/status_chip.dart';
import '../widgets/timeline_view.dart';

/// Detail screen for `/commitment/:id`.
///
/// [requestedDate] (query `?date=`) opens the check-in dialog for that day if
/// it can still be logged (used when opening from a reminder). [justLocked]
/// (`?locked=1`) plays the lock-settle animation.
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

  /// Optional day to log.
  final String? requestedDate;

  /// True right after the wizard locked the commitment.
  final bool justLocked;

  @override
  ConsumerState<CommitmentDetailScreen> createState() =>
      _CommitmentDetailScreenState();
}

class _CommitmentDetailScreenState
    extends ConsumerState<CommitmentDetailScreen> {
  bool _openedRequestedDate = false;

  /// Opens the reminder's day once the data is available.
  void _maybeOpenRequestedDate(Commitment c, CommitmentsState data) {
    final date = widget.requestedDate;
    if (_openedRequestedDate || date == null || !isValidDate(date)) return;
    _openedRequestedDate = true;
    if (!canApiCheckIn(c, data.snapshot.checkIns, date, data.now)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLogModal(context, LogSelection(c, date));
    });
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required String confirm,
    required Future<void> Function() action,
    String cancel = 'GO BACK',
    VoidCallback? onDone,
  }) async {
    final done = await showAppModal<bool>(
      context,
      builder: (_) => _ActionModal(
        title: title,
        message: message,
        confirm: confirm,
        cancel: cancel,
        action: action,
      ),
    );
    if (done == true && mounted) onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final controller = ref.read(commitmentsProvider.notifier);
    final c = data.snapshot.commitments
        .where((x) => x.id == widget.id)
        .firstOrNull;

    if (data.loading) {
      return const AppScreen(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [LockLoader(label: 'Preparing your check-in timeline')],
      );
    }
    if (c == null) {
      return AppScreen(
        header: AppHeader(back: true, onBack: () => context.go('/')),
        mainAxisAlignment: MainAxisAlignment.center,
        gap: 20,
        children: [
          const ScreenTitle('Commitment not found.', size: 30),
          const Label(
            'This link may belong to another account or the record was removed.',
            muted: true,
          ),
          LockButton(
            title: 'BACK TO DASHBOARD',
            onPressed: () => context.go('/'),
          ),
        ],
      );
    }
    _maybeOpenRequestedDate(c, data);

    final checkIns = data.snapshot.checkIns;
    final today = dateInZone(data.now, c.timeZone);
    final progress = apiProgress(c, checkIns, data.now);
    final end = apiEndDate(c);
    final active = c.status == CommitmentStatus.active;
    final paused = c.status == CommitmentStatus.paused;
    final completed = c.status == CommitmentStatus.completed;
    final broken = c.status == CommitmentStatus.broken;
    final showStreak = c.pace is DailyPace || c.pace is CustomPace;
    final streakInfo = showStreak ? streak(c, checkIns, data.now) : null;

    return AppScreen(
      header: const AppHeader(back: true, label: 'Back To Dashboard'),
      gap: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (data.error != null)
          Notice(data.error!, onRetry: controller.refresh),
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
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Label(
                  c.description.isNotEmpty
                      ? c.description
                      : 'A meaningful promise to yourself.',
                  size: 13,
                  muted: true,
                ),
              ),
            ],
          ),
        ),

        // ---- Timeline -------------------------------------------------------
        _Section(
          label: 'Timeline',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.inkFocus,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Label(
                      paceLabel(c.pace),
                      size: 12,
                      color: AppColors.onDark,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _DateBlock(label: 'Start Date', date: c.startDate),
                      _DateBlock(
                        label: paused ? 'End date (before resume)' : 'End Date',
                        date: end,
                      ),
                    ],
                  ),
                ),
                TimelineView(commitment: c, now: data.now),
                if (streakInfo != null)
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
                      'Paused. Your end date moves out by the paused days when '
                      'you resume.',
                      size: 11,
                      muted: true,
                    ),
                  ),
                if (broken)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Label(
                      '${c.breakReason ?? 'This attempt was broken.'} '
                      'Your history is preserved.',
                      size: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ---- Check-in calendar -----------------------------------------------
        _Section(
          label: 'Check-in Calendar',
          child: CheckInCalendar(
            commitment: c,
            checkIns: checkIns,
            today: today,
            onLogDay: (date) => showLogModal(context, LogSelection(c, date)),
          ),
        ),

        // ---- Today's check-in ------------------------------------------------
        _TodayCard(commitment: c, progress: progress, today: today),

        // ---- Reward ----------------------------------------------------------
        _Section(
          label: completed ? 'Reward Unlocked' : 'Reward At Finish',
          child: AppCard(
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
                        completed ? Feather.award : Feather.gift,
                        size: 64,
                        color: completed
                            ? AppColors.successForeground
                            : AppColors.inkPrimary,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Label(
                            'Unlocks at Day ${c.duration} (${formatDate(end)})',
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
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: LockButton(
                      light: true,
                      title: 'EDIT REWARD',
                      icon: Feather.edit2,
                      onPressed: () => showAppModal<void>(
                        context,
                        builder: (_) => _EditRewardModal(commitment: c),
                      ),
                    ),
                  ),
                const AppDivider(),
                Label(
                  completed
                      ? 'You kept the promise. It is time to enjoy what you earned.'
                      : 'Every single day you execute brings you closer to the reward.',
                  size: 11,
                  muted: true,
                  align: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        // ---- Commitment details ---------------------------------------------
        _Section(
          label: 'Commitment Details',
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _DetailRow(
                  'Type',
                  c.path == HabitPath.build ? 'Build habit' : 'Quit habit',
                ),
                _DetailRow(
                  'Check-ins',
                  '${progress.successfulCheckIns} logged',
                ),
                _DetailRow(
                  'Created',
                  formatDate(
                    dateInZone(DateTime.parse(c.createdAt), c.timeZone),
                  ),
                ),
                if (c.events.length > 1)
                  for (final e in c.events.skip(1))
                    _DetailRow(
                      '${e.type.name[0].toUpperCase()}${e.type.name.substring(1)}',
                      formatDate(e.date),
                    ),
              ],
            ),
          ),
        ),

        // ---- Lifecycle actions ----------------------------------------------
        if (broken)
          LockButton(
            light: true,
            title: 'RESTART COMMITMENT',
            icon: Feather.rotateCcw,
            onPressed: () => _restart(c),
          )
        else if (paused)
          LockButton(
            light: true,
            title: 'RESUME COMMITMENT',
            icon: Feather.play,
            onPressed: () => _confirm(
              title: 'Resume this commitment?',
              message: 'Your promise will become active again today.',
              confirm: 'RESUME COMMITMENT',
              action: () => controller.resume(c),
            ),
          )
        else if (active)
          LockButton(
            light: true,
            title: 'PAUSE COMMITMENT',
            icon: Feather.pause,
            onPressed: () => _confirm(
              title: 'Pause this commitment?',
              message:
                  'Pausing preserves your history; it does not record a '
                  'successful day. Your end date extends by the paused days '
                  'when you resume.',
              confirm: 'PAUSE COMMITMENT',
              cancel: 'KEEP GOING',
              action: () => controller.pause(c),
            ),
          ),
        LockButton(
          light: true,
          title: 'DELETE COMMITMENT',
          icon: Feather.trash2,
          onPressed: () => _confirm(
            title: 'Delete this commitment?',
            message:
                'This permanently deletes the commitment and its check-in '
                'history from your account. This cannot be undone.',
            confirm: 'DELETE',
            cancel: 'KEEP IT',
            action: () => controller.delete(c),
            onDone: () => context.go('/'),
          ),
        ),
      ],
    );
  }

  Future<void> _restart(Commitment c) async {
    final requestId = ref.read(uuidProvider)();
    Commitment? next;
    await _confirm(
      title: 'Start a fresh attempt?',
      message:
          'A new commitment with the same rules and reward starts today. '
          'This attempt and its history stay in your ledger.',
      confirm: 'START AGAIN',
      action: () async {
        next = await ref
            .read(commitmentsProvider.notifier)
            .restart(c, requestId, '', '');
      },
      onDone: () {
        final created = next;
        if (created != null) {
          context.pushReplacement('/commitment/${created.id}?locked=1');
        }
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [SectionLabel(label), child],
  );
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Label(label, size: 11, muted: true),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Label(formatDate(date), size: 12, bold: true),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    spacing: 12,
    children: [
      Label(label, size: 13, muted: true),
      Flexible(
        child: Label(value, size: 13, bold: true, align: TextAlign.right),
      ),
    ],
  );
}

/// "TODAY'S CHECK-IN": the question, the current period status, and the
/// buttons to answer it.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.commitment,
    required this.progress,
    required this.today,
  });

  final Commitment commitment;
  final ApiProgress progress;
  final String today;

  @override
  Widget build(BuildContext context) {
    final c = commitment;
    final active = c.status == CommitmentStatus.active;
    final quit = c.path == HabitPath.quit;
    final heading = switch (c.status) {
      CommitmentStatus.completed => 'Reward unlocked.',
      CommitmentStatus.paused => 'This commitment is paused.',
      CommitmentStatus.broken => 'This commitment is no longer active.',
      CommitmentStatus.active =>
        progress.checkedToday
            ? 'Today is logged.'
            : quit
            ? 'Did you keep your commitment?'
            : 'Did you show up today?',
    };
    final message = switch (c.status) {
      CommitmentStatus.active => progress.periodMessage,
      CommitmentStatus.paused => 'Resume it to start checking in again.',
      CommitmentStatus.broken =>
        c.breakReason ?? 'Your focus ledger is saved here.',
      CommitmentStatus.completed => 'Your focus ledger is saved here.',
    };
    final eligible = progress.eligibleToday;
    final String? hint = !active || progress.checkedToday || eligible
        ? null
        : today.compareTo(c.startDate) < 0
        ? 'Check-ins open on ${formatDate(c.startDate)}.'
        : today.compareTo(apiEndDate(c)) > 0
        ? 'The timeline has ended. Your result is being finalised.'
        : 'Today is not a scheduled day.';

    return AppCard(
      color: AppColors.surfacePanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Label("TODAY'S CHECK-IN", size: 11, muted: true),
          Label(heading, size: 22, bold: true),
          Label(message, size: 13),
          if (active && !progress.checkedToday) ...[
            if (quit) ...[
              LockButton(
                title: 'YES, KEPT IT',
                icon: Feather.check,
                disabled: !eligible,
                onPressed: () => showLogModal(context, LogSelection(c, today)),
              ),
              LockButton(
                light: true,
                title: 'NO, BROKEN',
                icon: Feather.x,
                disabled: !eligible,
                onPressed: () => showLogModal(
                  context,
                  LogSelection(c, today, startWithBreak: true),
                ),
              ),
            ] else
              LockButton(
                title: "LOG TODAY'S WIN",
                icon: Feather.check,
                disabled: !eligible,
                onPressed: () => showLogModal(context, LogSelection(c, today)),
              ),
            if (hint != null) Label(hint, size: 12, muted: true),
          ],
        ],
      ),
    );
  }
}

/// A confirmation dialog that runs [action] and pops `true` on success, or
/// shows the error and stays open.
class _ActionModal extends StatefulWidget {
  const _ActionModal({
    required this.title,
    required this.message,
    required this.confirm,
    required this.cancel,
    required this.action,
  });

  final String title;
  final String message;
  final String confirm;
  final String cancel;
  final Future<void> Function() action;

  @override
  State<_ActionModal> createState() => _ActionModalState();
}

class _ActionModalState extends State<_ActionModal> {
  bool _busy = false;
  String _error = '';

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is LockInException
              ? e.message
              : 'Unable to update this commitment. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ModalCard(
    title: widget.title,
    busy: _busy,
    children: [
      Label(widget.message),
      if (_error.isNotEmpty) ErrorNote(_error),
      LockButton(title: widget.confirm, loading: _busy, onPressed: _run),
      LockButton(
        light: true,
        title: widget.cancel,
        disabled: _busy,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ],
  );
}

/// "Update your reward" dialog (active commitments only).
class _EditRewardModal extends ConsumerStatefulWidget {
  const _EditRewardModal({required this.commitment});

  final Commitment commitment;

  @override
  ConsumerState<_EditRewardModal> createState() => _EditRewardModalState();
}

class _EditRewardModalState extends ConsumerState<_EditRewardModal> {
  late String _reward = widget.commitment.reward;
  bool _busy = false;
  String _error = '';

  Future<void> _save() async {
    final value = _reward.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Add a reward before saving.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ref
          .read(commitmentsProvider.notifier)
          .updateReward(widget.commitment, value);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is LockInException
              ? e.message
              : 'Unable to update the reward. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ModalCard(
    title: 'Update your reward',
    busy: _busy,
    children: [
      const Label('KEEP THE MOTIVATION REAL', size: 11, muted: true),
      const Label(
        'Change the reward whenever a better motivator comes to mind.',
      ),
      AppField(
        label: 'Reward',
        placeholder: 'e.g., A weekend getaway',
        value: _reward,
        maxLength: maxRewardLength,
        enabled: !_busy,
        onChanged: (v) => setState(() => _reward = v),
      ),
      if (_error.isNotEmpty) ErrorNote(_error),
      Row(
        spacing: 16,
        children: [
          Expanded(
            child: LockButton(
              light: true,
              title: 'CANCEL',
              disabled: _busy,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: LockButton(
              title: 'SAVE REWARD',
              loading: _busy,
              disabled: _reward.trim().isEmpty,
              onPressed: _save,
            ),
          ),
        ],
      ),
    ],
  );
}
