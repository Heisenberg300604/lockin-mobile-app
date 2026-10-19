/// A commitment summary card (Focus tab, "View all" lists, History).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';
import 'status_chip.dart';
import 'timeline_view.dart';

/// Tappable card that opens the commitment's detail screen.
class CommitmentCard extends ConsumerWidget {
  /// Creates a card for [commitment].
  const CommitmentCard({super.key, required this.commitment});

  /// The attempt to show.
  final Commitment commitment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(commitmentsProvider.select((s) => s.now));
    final checkIns = ref.watch(
      commitmentsProvider.select((s) => s.snapshot.checkIns),
    );
    final progress = apiProgress(commitment, checkIns, now);
    return MotionView(
      layout: true,
      child: Tappable(
        semanticLabel: 'Open ${commitment.name}',
        onTap: () => context.push('/commitment/${commitment.id}'),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Label(commitment.name, size: 19, bold: true)),
                  const SizedBox(width: 8),
                  StatusChip(commitment.status),
                ],
              ),
              if (commitment.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Label(
                    commitment.description,
                    size: 12,
                    muted: true,
                    maxLines: 2,
                  ),
                ),
              const SizedBox(height: 24),
              TimelineView(commitment: commitment, now: now),
              const SizedBox(height: 12),
              Label(
                '${progress.periodLabel}: ${progress.periodProgress} / ${progress.periodTarget}',
                size: 11,
                muted: true,
              ),
              const SizedBox(height: 20),
              Row(
                spacing: 6,
                children: [
                  const AppIcon(Feather.gift, size: 12),
                  Expanded(
                    child: Label(
                      'Reward Preview: ${commitment.reward}',
                      size: 11,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
