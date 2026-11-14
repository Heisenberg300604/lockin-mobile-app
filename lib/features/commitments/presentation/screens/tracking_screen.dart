/// "Today's Tracking" full list (reached by "View all" on the Focus tab).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/api_progress.dart';
import '../widgets/tracking_row.dart';

/// Every row due today plus unlogged days still inside the two-day backfill
/// window.
class TrackingScreen extends ConsumerWidget {
  /// Creates the screen.
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(commitmentsProvider);
    final rows = apiDueRows(data.snapshot, data.now);
    return AppScreen(
      header: const AppHeader(back: true, label: "Today's Tracking"),
      gap: 16,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        if (data.error != null)
          Notice(
            data.error!,
            onRetry: () => ref.read(commitmentsProvider.notifier).refresh(),
          ),
        if (rows.isEmpty) const Label('No commitments due today.'),
        for (final row in rows)
          TrackingRow(
            key: ValueKey('${row.commitment.id}${row.date}'),
            commitment: row.commitment,
            date: row.date,
            catchUp: row.catchUp,
            onPressed: () =>
                openCheckIn(context, ref, row.commitment, row.date),
          ),
      ],
    );
  }
}
