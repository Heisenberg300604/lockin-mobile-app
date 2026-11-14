/// The commitment's check-in calendar (web app: "CHECK-IN CALENDAR").
///
/// Every day shows what happened: logged on time, logged late (↺, a backfill),
/// broken, not logged (tappable while it can still be backfilled), backfill
/// window closed (struck through), upcoming, or inactive. A legend explains
/// the colours; the text is always available to screen readers.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/typography.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';

// Web palette for calendar states.
const _keptFill = Color(0xFFBFE1D2);
const _keptEdge = Color(0xFF0B775B);
const _keptToday = Color(0xFF08795B);
const _lateFill = Color(0xFFE8DCFF);
const _lateEdge = Color(0xFF6D38B1);
const _lateInk = Color(0xFF48206C);
const _brokenFill = Color(0xFFE4C0BD);
const _brokenEdge = Color(0xFFAD3026);
const _unloggedFill = Color(0xFFF3E4C8);
const _unloggedEdge = Color(0xFFB97922);
const _unloggedToday = Color(0xFFA66512);
const _upcomingInk = Color(0xFF766D65);
const _upcomingEdge = Color(0xFFD6CEC4);
const _inactiveInk = Color(0xFFB9B1A8);
const _expiredInk = Color(0xFFA69E96);

/// Month calendar for [commitment]. [onLogDay] is called when an unlogged day
/// inside the backfill window (or today) is tapped.
class CheckInCalendar extends StatefulWidget {
  /// Creates the calendar.
  const CheckInCalendar({
    super.key,
    required this.commitment,
    required this.checkIns,
    required this.today,
    required this.onLogDay,
  });

  /// The commitment being shown.
  final Commitment commitment;

  /// All check-ins (filtered to [commitment] internally).
  final List<CheckIn> checkIns;

  /// Today in the commitment's time zone.
  final String today;

  /// Called with a date that can be logged as kept.
  final ValueChanged<String> onLogDay;

  @override
  State<CheckInCalendar> createState() => _CheckInCalendarState();
}

class _CheckInCalendarState extends State<CheckInCalendar> {
  late String _month = _firstOfMonth(_initialDay());

  String _initialDay() {
    final c = widget.commitment;
    final today = widget.today;
    final inTimeline =
        today.compareTo(c.startDate) >= 0 &&
        today.compareTo(apiEndDate(c)) <= 0;
    return inTimeline ? today : c.startDate;
  }

  static String _firstOfMonth(String date) => '${date.substring(0, 7)}-01';

  @override
  Widget build(BuildContext context) {
    final c = widget.commitment;
    final offset = dayOfWeek(_month);
    final nextMonth = _firstOfMonth(addDays(_month, 32));
    final length = dayDifference(_month, nextMonth);
    final rows = (offset + length + 6) ~/ 7;

    Widget cell(int i) {
      if (i < offset || i >= offset + length) {
        return const SizedBox(height: 40);
      }
      final date = addDays(_month, i - offset);
      final state = apiCalendarState(c, widget.checkIns, date, widget.today);
      final isToday = date == widget.today;
      final tappable = state == CalendarDayState.unlogged;
      return _DayCell(
        day: i - offset + 1,
        state: state,
        isToday: isToday,
        semanticLabel:
            '${formatDate(date)}: ${calendarStateLabel(state)}'
            '${tappable ? '. Log as kept' : ''}',
        onTap: tappable ? () => widget.onLogDay(date) : null,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
      decoration: BoxDecoration(
        color: AppColors.surfacePanel,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconBtn(
                icon: Feather.chevronLeft,
                label: 'Show previous month',
                onPressed: () =>
                    setState(() => _month = _firstOfMonth(addDays(_month, -1))),
              ),
              Label(formatMonthYear(_month), size: 16, bold: true),
              IconBtn(
                icon: Feather.chevronRight,
                label: 'Show next month',
                onPressed: () => setState(() => _month = nextMonth),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: Center(child: Label(w, size: 10, muted: true)),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < rows; row++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(child: cell(row * 7 + col)),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFDED6CB))),
            ),
            child: Semantics(
              label: 'Calendar status legend',
              child: Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  const _LegendItem(
                    label: 'Logged on time',
                    fill: _keptFill,
                    edge: _keptEdge,
                  ),
                  const _LegendItem(
                    label: '↺ Logged late',
                    fill: _lateFill,
                    edge: _lateEdge,
                    ink: _lateInk,
                  ),
                  const _LegendItem(
                    label: 'Not logged',
                    fill: _unloggedFill,
                    edge: _unloggedEdge,
                  ),
                  const _LegendItem(
                    label: 'Upcoming',
                    fill: Color(0xFFF8F5EF),
                    edge: _upcomingEdge,
                  ),
                  if (c.path == HabitPath.quit)
                    const _LegendItem(
                      label: 'Broken',
                      fill: _brokenFill,
                      edge: _brokenEdge,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Label(
            'Missed a day? Tap a “not logged” day from the last two days to '
            'backfill it.',
            size: 11,
            muted: true,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.state,
    required this.isToday,
    required this.semanticLabel,
    required this.onTap,
  });

  final int day;
  final CalendarDayState state;
  final bool isToday;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color? fill;
    Color? edge;
    var edgeWidth = 1.0;
    var ink = AppColors.inkPrimary;
    var strike = false;

    switch (state) {
      case CalendarDayState.keptOnTime:
        fill = isToday ? _keptToday : _keptFill;
        edge = isToday ? const Color(0xFF075039) : _keptEdge;
        edgeWidth = 2;
      case CalendarDayState.keptLate:
        fill = isToday ? _lateEdge : _lateFill;
        edge = isToday ? _lateInk : _lateEdge;
        edgeWidth = 2;
        ink = _lateInk;
      case CalendarDayState.broken:
        fill = isToday ? _brokenEdge : _brokenFill;
        edge = isToday ? const Color(0xFF7D1F18) : _brokenEdge;
        edgeWidth = 2;
      case CalendarDayState.unlogged:
        fill = isToday ? _unloggedToday : _unloggedFill;
        edge = isToday ? const Color(0xFF754303) : _unloggedEdge;
      case CalendarDayState.upcoming:
        edge = _upcomingEdge;
        ink = _upcomingInk;
      case CalendarDayState.expired:
        ink = _expiredInk;
        strike = true;
      case CalendarDayState.outside:
      case CalendarDayState.notScheduled:
      case CalendarDayState.ended:
      case CalendarDayState.unavailable:
        ink = _inactiveInk;
    }
    if (isToday) {
      // Today is a dark circle; states tint it, as on the web.
      fill ??= AppColors.inkPrimary;
      edge = state == CalendarDayState.upcoming ? null : edge;
      ink = AppColors.onDark;
    }

    final late = state == CalendarDayState.keptLate;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            height: 38,
            width: isToday ? 38 : null,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: fill,
              shape: isToday ? BoxShape.circle : BoxShape.rectangle,
              border: edge == null
                  ? null
                  : Border.all(color: edge, width: edgeWidth),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      decoration: strike ? TextDecoration.lineThrough : null,
                      decorationColor: ink,
                    ),
                  ),
                ),
                if (late)
                  Positioned(
                    right: isToday ? 6 : 3,
                    bottom: 1,
                    child: Text(
                      '↺',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isToday ? AppColors.onDark : _lateEdge,
                      ),
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

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.fill,
    required this.edge,
    this.ink,
  });

  final String label;
  final Color fill;
  final Color edge;
  final Color? ink;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: edge),
        ),
      ),
      Label(label, size: 10, bold: true, color: ink ?? AppColors.inkSecondary),
    ],
  );
}
