/// The History tab: pick a day, see what was scheduled, and browse past
/// (completed or broken) attempts.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../widgets/calendar_view.dart';
import '../widgets/commitment_card.dart';
import '../widgets/log_modal.dart';
import '../widgets/status_chip.dart';
import '../widgets/tracking_row.dart';

/// History tab. [initialDate] comes from `/history?date=yyyy-MM-dd`.
class HistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HistoryScreen({super.key, this.initialDate});

  /// Day to open on, if a valid date was passed in the URL.
  final String? initialDate;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late String _date;

  bool _valid(String? d) => d != null && isValidDate(d);

  @override
  void initState() {
    super.initState();
    _date = _valid(widget.initialDate)
        ? widget.initialDate!
        : dateInZone(ref.read(commitmentsProvider).now);
  }

  @override
  void didUpdateWidget(HistoryScreen old) {
    super.didUpdateWidget(old);
    // Tapping a different day in the Focus week strip updates the URL; follow it.
    if (_valid(widget.initialDate) && widget.initialDate != old.initialDate) {
      _date = widget.initialDate!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final entries = data.snapshot.commitments.where((c) => isScheduled(c, _date)).toList();
    final past = data.snapshot.commitments
        .where((c) => c.status == CommitmentStatus.completed || c.status == CommitmentStatus.broken)
        .toList();

    return AppScreen(
      header: const AppHeader(),
      gap: 24,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const SectionLabel('History'),
        if (data.error != null)
          Notice(data.error!, onRetry: () => ref.read(commitmentsProvider.notifier).refresh()),
        CalendarView(
          selected: _date,
          onSelect: (d) => setState(() => _date = d),
        ),
        Label(formatDate(_date), bold: true),
        if (entries.isNotEmpty)
          for (final c in entries)
            Column(
              key: ValueKey(c.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: StatusChip(c.status)),
                TrackingRow(
                  commitment: c,
                  date: _date,
                  onPressed: () => canApiCheckIn(c, _date, data.now)
                      ? showLogModal(context, LogSelection(c, _date))
                      : context.push('/commitment/${c.id}'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Tappable(
                    semanticLabel: 'Details for ${c.name}',
                    onTap: () => context.push('/commitment/${c.id}'),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Label('View commitment →', size: 11, muted: true),
                    ),
                  ),
                ),
              ],
            )
        else
          const Label('No commitments scheduled for this date.', size: 13, muted: true),
        const SectionLabel('Past attempts'),
        for (final c in past) CommitmentCard(key: ValueKey('past${c.id}'), commitment: c),
        if (past.isEmpty)
          const Label('Your completed and broken attempts will stay here.', size: 13, muted: true),
      ],
    );
  }
}
