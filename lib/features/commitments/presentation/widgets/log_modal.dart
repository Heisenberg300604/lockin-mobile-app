/// The "Daily Log Progress" dialog: record today's result, or a catch-up day.
///
/// Three layouts, chosen from the commitment's pace:
/// * numeric (a daily count above 1): a [Counter] and "Apply Changes";
/// * binary: one big "Done!" / "Stayed Consistent" button;
/// * both offer a negative outcome that first asks for confirmation, because
///   for daily paces it ends the attempt.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/counter.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';

/// Which attempt and day the dialog is for.
class LogSelection {
  /// Creates a selection.
  const LogSelection(this.commitment, this.date);

  /// The attempt.
  final Commitment commitment;

  /// The day to log.
  final String date;
}

/// Opens the log dialog for [selection].
Future<void> showLogModal(BuildContext context, LogSelection selection) {
  // Captured now because the dialog's own context disappears when it closes,
  // but we may need to navigate afterwards (to the reflection screen).
  final router = GoRouter.of(context);
  return showAppModal<void>(
    context,
    builder: (_) => _LogModalBody(selection: selection, router: router),
  );
}

class _LogModalBody extends ConsumerStatefulWidget {
  const _LogModalBody({required this.selection, required this.router});

  final LogSelection selection;
  final GoRouter router;

  @override
  ConsumerState<_LogModalBody> createState() => _LogModalBodyState();
}

class _LogModalBodyState extends ConsumerState<_LogModalBody> {
  late int _count;
  bool _busy = false;
  bool _confirmFailure = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // Start the counter from the saved value. Later background refreshes must
    // not overwrite what the user is editing, so this runs only once.
    final data = ref.read(commitmentsProvider);
    _count = getLog(data.snapshot.checkIns, widget.selection.commitment, widget.selection.date)
            ?.count ??
        0;
  }

  Future<void> _save(Commitment c, int value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ref.read(commitmentsProvider.notifier).log(c, widget.selection.date, value);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is LockInException ? e.message : 'Your check-in was not saved. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordFailure(Commitment c) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ref.read(commitmentsProvider.notifier).fail(c, widget.selection.date);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (c.pace is! WeeklyPace) {
        unawaited(widget.router.push('/commitment/${c.id}/reflect'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is LockInException ? e.message : 'Your outcome was not saved. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final date = widget.selection.date;
    // Use the freshest copy of the commitment (it may have changed since the
    // dialog opened), falling back to the one we were given.
    final c = data.snapshot.commitments
            .where((x) => x.attemptId == widget.selection.commitment.attemptId)
            .firstOrNull ??
        widget.selection.commitment;
    final enabled = canApiCheckIn(c, date, data.now);
    final numeric = c.pace is DailyPace && (c.pace as DailyPace).count > 1;
    final weekly = c.pace is WeeklyPace;
    final period = weekly ? weeklyPeriod(c, date) : null;
    final quit = c.path == HabitPath.quit;

    final subtitle = period != null
        ? '${formatDate(date)}\n${period.required} successful days · '
            '${formatShortDate(period.start)} – ${formatShortDate(period.end)}'
        : '${formatDate(date)}\nEvery single day brings you closer to your reward.';

    return ModalCard(
      title: 'Daily Log Progress',
      busy: _busy,
      children: [
        Label(c.name, size: 24, bold: true, align: TextAlign.center),
        Label(subtitle, muted: true, align: TextAlign.center),
        if (_confirmFailure) ...[
          Label(
            weekly
                ? 'Record this date as missed? Your weekly commitment continues until its quota deadline.'
                : 'This will end this attempt now. Your history stays saved, and you can reflect and start again.',
          ),
          LockButton(
            title: weekly ? 'CONFIRM MISSED DAY' : 'CONFIRM & END ATTEMPT',
            onPressed: () => _recordFailure(c),
            loading: _busy,
            disabled: !enabled,
          ),
          LockButton(
            light: true,
            title: 'KEEP GOING',
            onPressed: () => setState(() => _confirmFailure = false),
            disabled: _busy,
          ),
        ] else ...[
          if (numeric) ...[
            Counter(value: _count, max: targetForDate(c), onChanged: (v) => setState(() => _count = v)),
            Label('of ${targetForDate(c)} today', size: 12, muted: true, align: TextAlign.center),
            LockButton(
              title: 'Apply Changes',
              onPressed: () => _save(c, _count),
              loading: _busy,
              disabled: !enabled,
            ),
          ] else
            LockButton(
              light: true,
              title: quit ? 'Stayed Consistent' : 'Done!',
              icon: Feather.check,
              onPressed: () => _save(c, 1),
              loading: _busy,
              disabled: !enabled,
            ),
          LockButton(
            light: true,
            title: weekly
                ? (quit ? "Didn't stay consistent" : 'Not today')
                : (quit ? 'Broke my Commitment' : 'Missed'),
            icon: Feather.x,
            onPressed: () => setState(() => _confirmFailure = true),
            disabled: !enabled || _busy,
          ),
        ],
        if (_error.isNotEmpty) ErrorNote(_error),
        if (!enabled) const Label('Check-ins are available for today only.', size: 12, muted: true),
        const Label(
          'LockIn records one server-verified result for today.',
          size: 11,
          muted: true,
          align: TextAlign.center,
        ),
      ],
    );
  }
}
