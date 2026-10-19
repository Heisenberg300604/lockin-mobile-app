/// "Day 12 / 30  ·  18 Days Remaining" with a progress line.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/typography.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';

/// Shows how far through its timeline an attempt is.
class TimelineView extends StatelessWidget {
  /// Creates a timeline for [commitment] as of [now].
  const TimelineView({super.key, required this.commitment, required this.now});

  /// The attempt.
  final Commitment commitment;

  /// Current time (used to work out "today").
  final DateTime now;

  String _caption(String today, int day) {
    switch (commitment.status) {
      case CommitmentStatus.broken:
        return 'Ended ${formatShortDate(commitment.failureDate ?? today)}';
      case CommitmentStatus.completed:
        return 'Promise kept';
      case CommitmentStatus.paused:
        final since = commitment.events
            .where((e) => e.type == LifecycleEventType.paused)
            .map((e) => e.date)
            .lastOrNull;
        return 'Paused since ${formatShortDate(since ?? today)}';
      case CommitmentStatus.active:
        if (day == 0) return 'Starts ${formatShortDate(commitment.startDate)}';
        if (today.compareTo(endDate(commitment)) > 0) return 'Timeline ended';
        return '${commitment.duration - day} Days Remaining';
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = dateInZone(now, commitment.timeZone);
    final day = dayOrdinal(commitment, today);
    final fraction = (day / commitment.duration).clamp(0.0, 1.0);
    final icon = switch (commitment.status) {
      CommitmentStatus.broken => Feather.x,
      CommitmentStatus.paused => Feather.pause,
      _ => Feather.check,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: 12,
          children: [
            Label('Day $day / ${commitment.duration}', size: 13, bold: true),
            Flexible(child: Label(_caption(today, day), size: 11, align: TextAlign.right)),
          ],
        ),
        // NOTE: no LayoutBuilder here on purpose. Screens measure their
        // children's natural height (SliverFillRemaining in AppScreen), and
        // LayoutBuilder cannot be measured that way. Proportional sizing is
        // done with FractionallySizedBox / Align instead.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Track (white) and progress (dark) lines.
                const Positioned.fill(child: ColoredBox(color: AppColors.surfaceInput)),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.inkPrimary),
                    ),
                  ),
                ),
                // Hollow end marker.
                Positioned(
                  right: 0,
                  top: -4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceCard,
                      border: Border.all(color: AppColors.inkPrimary),
                    ),
                  ),
                ),
                // Current position marker: slides from the left edge (0) to
                // the right edge (1) of the line.
                Positioned.fill(
                  child: OverflowBox(
                    maxHeight: 14,
                    child: Align(
                      alignment: Alignment(fraction * 2 - 1, 0),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.inkPrimary,
                        ),
                        child: AppIcon(icon, size: 9, color: AppColors.onDark),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
