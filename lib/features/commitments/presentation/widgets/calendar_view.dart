/// A month calendar used in three places:
///
/// 1. the custom-duration picker in the creation wizard (range highlight),
/// 2. the History tab (pick a day),
/// 3. the commitment detail screen (completed / missed / paused days).
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/typography.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';

/// Month grid, Monday first.
///
/// With a [commitment] each day is coloured by what happened that day. Without
/// one it is a plain date picker.
class CalendarView extends StatefulWidget {
  /// Creates a calendar.
  const CalendarView({
    super.key,
    this.selected,
    this.onSelect,
    this.rangeStart,
    this.rangeEnd,
    this.commitment,
    this.logs = const [],
  });

  /// The highlighted day (`yyyy-MM-dd`), also decides the visible month.
  final String? selected;

  /// Called when a day is tapped.
  final ValueChanged<String>? onSelect;

  /// Start of a highlighted range.
  final String? rangeStart;

  /// End of a highlighted range.
  final String? rangeEnd;

  /// When set, days are coloured by this attempt's history.
  final Commitment? commitment;

  /// Check-ins to read (used with [commitment]).
  final List<CheckIn> logs;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late String _month = _firstOfMonth(widget.selected ?? dateInZone(DateTime.now(), widget.commitment?.timeZone));

  static String _firstOfMonth(String date) => '${date.substring(0, 7)}-01';

  @override
  void didUpdateWidget(CalendarView old) {
    super.didUpdateWidget(old);
    // Jump to the month of a newly selected day (e.g. picked from the week strip).
    if (widget.selected != null && widget.selected != old.selected) {
      _month = _firstOfMonth(widget.selected!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commitment = widget.commitment;
    final today = dateInZone(DateTime.now(), commitment?.timeZone);
    final offset = dayOfWeek(_month);
    final nextMonth = _firstOfMonth(addDays(_month, 32));
    final length = dayDifference(_month, nextMonth);
    final cellCount = ((offset + length + 6) ~/ 7) * 7;

    Widget cell(int i) {
      if (i < offset || i >= offset + length) return const SizedBox(height: 40);
      final date = addDays(_month, i - offset);
      final count = commitment == null ? 0 : (getLog(widget.logs, commitment, date)?.count ?? 0);
      final done = commitment != null && count >= targetForDate(commitment);
      final active = date == widget.selected;
      final current = date == today;
      final missed = commitment != null &&
          (commitment.failureDate == date ||
              getLog(widget.logs, commitment, date)?.outcome == CheckInOutcome.missed);
      final paused = commitment != null && isPausedDate(commitment, date);
      final inRange = widget.rangeStart != null &&
          widget.rangeEnd != null &&
          date.compareTo(widget.rangeStart!) >= 0 &&
          date.compareTo(widget.rangeEnd!) <= 0;

      // Later rules override earlier ones, same as the original style array.
      Color? background;
      if (inRange) background = AppColors.surfaceCard;
      if (done) background = AppColors.calendarSuccess;
      if (missed) background = AppColors.dangerBackground;
      if (current) background = AppColors.inkPrimary;

      final dim = commitment != null && !isScheduled(commitment, date);
      final label = '${formatDate(date)}${done ? ', completed' : ''}${missed ? ', missed' : ''}'
          '${paused ? ', paused' : ''}${active ? ', selected' : ''}';

      return Semantics(
        button: widget.onSelect != null,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect == null ? null : () => widget.onSelect!(date),
          child: CustomPaint(
            foregroundPainter: (paused || active)
                ? _CellBorderPainter(
                    color: active ? AppColors.successForeground : AppColors.inkMuted,
                    dashed: paused,
                    radius: current ? 24 : 0,
                  )
                : null,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: current ? BorderRadius.circular(24) : null,
              ),
              child: Label(
                '${i - offset + 1}',
                size: 12,
                bold: current,
                color: current
                    ? AppColors.onDark
                    : dim
                        ? AppColors.inkMuted
                        : AppColors.inkPrimary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfacePanel,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconBtn(
                  icon: Feather.chevronLeft,
                  label: 'Previous month',
                  onPressed: () => setState(() => _month = _firstOfMonth(addDays(_month, -1))),
                ),
                Label(formatMonthYear(_month), size: 14, bold: true),
                IconBtn(
                  icon: Feather.chevronRight,
                  label: 'Next month',
                  onPressed: () => setState(() => _month = nextMonth),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final w in weekdayNames)
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: Center(child: Label(w.substring(0, 1), size: 10, muted: true)),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < cellCount ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++) Expanded(child: cell(row * 7 + col)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Draws a 1px border, optionally dashed, around a calendar cell.
class _CellBorderPainter extends CustomPainter {
  const _CellBorderPainter({required this.color, required this.dashed, required this.radius});

  final Color color;
  final bool dashed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = (Offset.zero & size).deflate(0.5);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    // Walk along the outline drawing 3px dashes separated by 3px gaps.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 3), paint);
        distance += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_CellBorderPainter old) =>
      old.color != color || old.dashed != dashed || old.radius != radius;
}
