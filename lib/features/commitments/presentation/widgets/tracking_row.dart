/// One line of "Today's Tracking": name, progress bar, and a check box.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/raised_box.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../application/commitments_controller.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import 'log_modal.dart';

/// Opens the check-in dialog for [date] when the server will still accept
/// it, otherwise the commitment's detail screen.
void openCheckIn(
  BuildContext context,
  WidgetRef ref,
  Commitment c,
  String date,
) {
  final data = ref.read(commitmentsProvider);
  if (canApiCheckIn(c, data.snapshot.checkIns, date, data.now)) {
    showLogModal(context, LogSelection(c, date));
  } else {
    context.push('/commitment/${c.id}');
  }
}

/// A tappable tracking row. Opens the log dialog via [onPressed].
class TrackingRow extends ConsumerWidget {
  /// Creates a row for [commitment] on [date].
  const TrackingRow({
    super.key,
    required this.commitment,
    required this.date,
    required this.onPressed,
    this.catchUp = false,
  });

  /// The attempt.
  final Commitment commitment;

  /// The day this row is for.
  final String date;

  /// Called on tap.
  final VoidCallback onPressed;

  /// Whether [date] is an earlier day being caught up.
  final bool catchUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkIns = ref.watch(
      commitmentsProvider.select((s) => s.snapshot.checkIns),
    );
    final now = ref.watch(commitmentsProvider.select((s) => s.now));
    // Progress of the API rule period containing [date]; the tick shows
    // whether [date] itself is logged as kept.
    final period = apiProgress(commitment, checkIns, now, onDate: date);
    final entry = apiCheckInOn(checkIns, commitment, date);
    final p = (
      count: period.periodProgress,
      target: period.periodTarget,
      done: entry?.outcome == CheckInOutcome.success,
    );
    final suffix = switch (commitment.pace) {
      WeeklyPace() || CustomPace() => ' wk',
      MonthlyPace() => ' mo',
      _ => '',
    };
    final caption = catchUp
        ? 'Not logged · ${formatShortDate(date)} · tap to backfill'
        : entry?.outcome == CheckInOutcome.missed
        ? 'Broken today'
        : paceLabel(commitment.pace);

    return MotionView(
      layout: true,
      child: Tappable(
        semanticLabel:
            '${commitment.name}, ${p.count} of ${p.target}${catchUp ? ', catch up for ${formatDate(date)}' : ''}',
        onTap: onPressed,
        child: RaisedBox(
          dx: 2,
          dy: 3,
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceTracking,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label(commitment.name, bold: true),
                      Label(caption, size: 11, muted: true),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          spacing: 4,
                          children: [
                            Expanded(
                              flex: 77,
                              child: AppProgressBar(
                                value: p.target == 0 ? 0 : p.count / p.target,
                              ),
                            ),
                            Expanded(
                              flex: 23,
                              child: Label(
                                '${p.count}/${p.target}$suffix',
                                size: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                StateMotion(
                  value: p.done,
                  settle: true,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.done
                          ? AppColors.successForeground
                          : AppColors.surfaceInput,
                      border: Border.all(
                        color: p.done
                            ? AppColors.successForeground
                            : AppColors.placeholder,
                      ),
                    ),
                    child: p.done
                        ? const OverflowBox(
                            maxWidth: 12,
                            maxHeight: 12,
                            child: AppIcon(
                              Feather.check,
                              size: 12,
                              color: AppColors.onDark,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
