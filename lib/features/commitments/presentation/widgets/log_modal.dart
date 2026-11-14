/// The check-in dialog, matching the LockIn web app:
///
/// * **Today** – "Log today's activity?" for a build habit; for a quit habit
///   "Did you keep your commitment?" with *Yes, kept it* / *No, broken*.
/// * **Backfill** – an unlogged day inside the two-day window can be logged
///   as kept ("Log Jun 3 as kept?"). Backfills are always kept.
/// * **Break** – "Why did it unlock?": a reason and an optional private note
///   are saved with the broken check-in and end the attempt.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_field.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';

/// Which commitment and day the dialog is for.
class LogSelection {
  /// Creates a selection. With [startWithBreak] a quit habit opens directly
  /// on the "Why did it unlock?" step.
  const LogSelection(this.commitment, this.date, {this.startWithBreak = false});

  /// The commitment.
  final Commitment commitment;

  /// The day to log.
  final String date;

  /// Open on the break step (quit habits, today only).
  final bool startWithBreak;
}

/// The preset reasons offered when a quit habit breaks (web app wording).
const breakReasons = [
  'Low energy',
  'Time crunch',
  'Lack of focus',
  'Social plans',
];

/// Opens the check-in dialog for [selection].
Future<void> showLogModal(BuildContext context, LogSelection selection) =>
    showAppModal<void>(
      context,
      builder: (_) => _LogModalBody(selection: selection),
    );

class _LogModalBody extends ConsumerStatefulWidget {
  const _LogModalBody({required this.selection});

  final LogSelection selection;

  @override
  ConsumerState<_LogModalBody> createState() => _LogModalBodyState();
}

class _LogModalBodyState extends ConsumerState<_LogModalBody> {
  late bool _breaking = widget.selection.startWithBreak;
  String _reason = breakReasons.first;
  String _note = '';
  bool _busy = false;
  String _error = '';

  Future<void> _run(Future<void> Function() action, String fallback) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is LockInException ? e.message : fallback);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keep(Commitment c) => _run(
    () =>
        ref.read(commitmentsProvider.notifier).log(c, widget.selection.date, 1),
    'Unable to record this check-in. Please retry.',
  );

  Future<void> _break(Commitment c) => _run(
    () => ref
        .read(commitmentsProvider.notifier)
        .fail(c, widget.selection.date, reason: _reason, note: _note),
    'Unable to record this check-in. Please retry.',
  );

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final date = widget.selection.date;
    // Use the freshest copy of the commitment; fall back to the one given.
    final c =
        data.snapshot.commitments
            .where((x) => x.attemptId == widget.selection.commitment.attemptId)
            .firstOrNull ??
        widget.selection.commitment;
    final today = dateInZone(data.now, c.timeZone);
    final backfill = date != today;
    final quit = c.path == HabitPath.quit;
    // Keep the dialog usable while its own save refreshes the data.
    final enabled =
        _busy || canApiCheckIn(c, data.snapshot.checkIns, date, data.now);

    final List<Widget> body;
    final String title;
    if (_breaking && quit && !backfill) {
      title = 'Why did it unlock?';
      body = [
        const Label('NO JUDGMENT. JUST DATA.', size: 11, muted: true),
        const Label(
          'Admitting a slip is part of the process. Your private history will '
          'record it transparently.',
        ),
        for (var row = 0; row < breakReasons.length; row += 2)
          Row(
            spacing: 12,
            children: [
              for (final r in breakReasons.skip(row).take(2))
                Expanded(
                  child: LockButton(
                    light: true,
                    title: r,
                    selected: _reason == r,
                    disabled: _busy,
                    onPressed: () => setState(() => _reason = r),
                  ),
                ),
            ],
          ),
        AppField(
          semanticLabel: 'What caused the breach? (optional)',
          placeholder: 'What caused the breach? (optional)',
          multiline: true,
          minHeight: 72,
          maxLength: 1000,
          value: _note,
          enabled: !_busy,
          onChanged: (v) => setState(() => _note = v),
        ),
        const Label(
          'This ends the current attempt. Your history stays saved, and you can '
          'restart from the commitment screen.',
          size: 12,
          muted: true,
        ),
        LockButton(
          title: 'SECURE LOG',
          loading: _busy,
          disabled: !enabled,
          onPressed: () => _break(c),
        ),
        LockButton(
          light: true,
          title: 'KEEP GOING',
          disabled: _busy,
          onPressed: () => widget.selection.startWithBreak
              ? Navigator.of(context).pop()
              : setState(() => _breaking = false),
        ),
      ];
    } else if (backfill) {
      title = 'Log ${formatDate(date)} as kept?';
      body = [
        const Label('HONEST PROGRESS', size: 11, muted: true),
        Label(c.name, size: 20, bold: true),
        const Label(
          'This saves the completed commitment for that date in your permanent '
          'history. It will show as logged late.',
        ),
        _actions(c, confirm: 'YES, LOG IT', enabled: enabled),
      ];
    } else if (quit) {
      title = 'Did you keep your commitment?';
      body = [
        const Label('HONEST PROGRESS', size: 11, muted: true),
        Label(c.name, size: 20, bold: true),
        Label('${formatDate(date)} · Kept or broken — an honest record.'),
        LockButton(
          title: 'YES, KEPT IT',
          icon: Feather.check,
          loading: _busy,
          disabled: !enabled,
          onPressed: () => _keep(c),
        ),
        LockButton(
          light: true,
          title: 'NO, BROKEN',
          icon: Feather.x,
          disabled: !enabled || _busy,
          onPressed: () => setState(() => _breaking = true),
        ),
      ];
    } else {
      title = "Log today's activity?";
      body = [
        const Label('HONEST PROGRESS', size: 11, muted: true),
        Label(c.name, size: 20, bold: true),
        const Label(
          'This records today as kept in your permanent commitment history. '
          'Your calendar will update when it is saved.',
        ),
        _actions(c, confirm: 'YES, LOG IT', enabled: enabled),
      ];
    }

    return ModalCard(
      title: title,
      busy: _busy,
      children: [
        ...body,
        if (_error.isNotEmpty) ErrorNote(_error),
        if (!enabled)
          const Label(
            'This day can no longer be logged. Check-ins are open for today and '
            'the previous two days.',
            size: 12,
            muted: true,
          ),
      ],
    );
  }

  Widget _actions(
    Commitment c, {
    required String confirm,
    required bool enabled,
  }) => Row(
    spacing: 16,
    children: [
      Expanded(
        child: LockButton(
          light: true,
          title: 'GO BACK',
          disabled: _busy,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      Expanded(
        child: LockButton(
          title: confirm,
          loading: _busy,
          disabled: !enabled,
          onPressed: () => _keep(c),
        ),
      ),
    ],
  );
}
