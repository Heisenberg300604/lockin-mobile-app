/// Full list of Build or Quit commitments ("View all" on the Focus tab).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../widgets/commitment_card.dart';

/// Lists current commitments, optionally filtered by [path] and [status]
/// (both come from the URL query: `/commitments?path=build&status=active`).
class CommitmentsListScreen extends ConsumerWidget {
  /// Creates the screen.
  const CommitmentsListScreen({super.key, this.path, this.status});

  /// `build` or `quit`, or `null` for both.
  final String? path;

  /// A status name, `all`, or `null`.
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(commitmentsProvider.select((s) => s.snapshot));
    final cards = snapshot.commitments
        .where(
          (c) =>
              (path == null || c.path.name == path) &&
              (status == null || status == 'all' || c.status.name == status) &&
              c.status != CommitmentStatus.completed &&
              c.restartedBy == null,
        )
        .toList();
    return AppScreen(
      header: AppHeader(
        back: true,
        label: path == 'quit' ? 'Quitting Habits' : 'Building Habits',
      ),
      gap: 16,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        for (final c in cards) CommitmentCard(key: ValueKey(c.id), commitment: c),
        if (cards.isEmpty) const Label('No matching commitments found.'),
      ],
    );
  }
}
