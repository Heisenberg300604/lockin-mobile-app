/// The dialog for "Flexible Pace" (N times a day/week) and "Custom Days".
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/widgets/counter.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/modal_card.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../domain/api_progress.dart';
import '../../domain/models.dart';
import '../../domain/validation.dart';

/// Which editor to show (web app: flexible weekly pace, flexible monthly
/// pace, fixed weekly schedule).
enum PaceEditorMode { weekly, monthly, customDays }

/// Opens the pace editor. Returns the chosen [Pace], or `null` if dismissed.
///
/// [draft] provides context for validation: the target must be achievable in
/// every (possibly partial) week or month of the timeline, as the API checks.
Future<Pace?> showPaceEditor(
  BuildContext context, {
  required Draft draft,
  required PaceEditorMode mode,
}) {
  final initial = switch (mode) {
    PaceEditorMode.customDays =>
      draft.pace is CustomPace ? draft.pace : const CustomPace([0]),
    PaceEditorMode.weekly =>
      draft.pace is WeeklyPace ? draft.pace : const WeeklyPace(3),
    PaceEditorMode.monthly =>
      draft.pace is MonthlyPace ? draft.pace : const MonthlyPace(15),
  };
  return showAppModal<Pace>(
    context,
    builder: (_) => _PaceEditor(draft: draft, initial: initial, mode: mode),
  );
}

class _PaceEditor extends StatefulWidget {
  const _PaceEditor({
    required this.draft,
    required this.initial,
    required this.mode,
  });

  final Draft draft;
  final Pace initial;
  final PaceEditorMode mode;

  @override
  State<_PaceEditor> createState() => _PaceEditorState();
}

class _PaceEditorState extends State<_PaceEditor> {
  late Pace _pace = widget.initial;
  String _error = '';

  void _apply() {
    // Validate against the whole draft, filling the fields not entered yet.
    final problem =
        validateDraft(
          widget.draft.copyWith(
            name: widget.draft.name.isEmpty ? 'Target' : widget.draft.name,
            reward: widget.draft.reward.isEmpty
                ? 'Reward'
                : widget.draft.reward,
            pace: _pace,
          ),
        ) ??
        apiFeasibilityError(
          startDate: widget.draft.startDate,
          duration: widget.draft.duration,
          pace: _pace,
        );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(_pace);
  }

  @override
  Widget build(BuildContext context) {
    final pace = _pace;
    return ModalCard(
      title: switch (widget.mode) {
        PaceEditorMode.weekly => 'Flexible weekly pace',
        PaceEditorMode.monthly => 'Flexible monthly pace',
        PaceEditorMode.customDays => 'Fixed weekly schedule',
      },
      children: [
        if (pace is CustomPace) ...[
          const Label(
            'Each selected weekday is required before the week closes.',
            muted: true,
          ),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: LockButton(
                  light: true,
                  title: 'Weekdays',
                  onPressed: () =>
                      setState(() => _pace = const CustomPace([0, 1, 2, 3, 4])),
                ),
              ),
              Expanded(
                child: LockButton(
                  light: true,
                  title: 'Weekends',
                  onPressed: () =>
                      setState(() => _pace = const CustomPace([5, 6])),
                ),
              ),
            ],
          ),
          const Label(
            'OR SELECT SPECIFIC DAYS',
            size: 11,
            muted: true,
            align: TextAlign.center,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < weekdayNames.length; i++)
                _DayToggle(
                  label: weekdayNames[i],
                  selected: pace.days.contains(i),
                  onTap: () => setState(() {
                    _error = '';
                    _pace = CustomPace(
                      pace.days.contains(i)
                          ? pace.days.where((d) => d != i).toList()
                          : ([...pace.days, i]..sort()),
                    );
                  }),
                ),
            ],
          ),
        ] else ...[
          Label(
            pace is MonthlyPace
                ? 'Meet this minimum on any days in the month. Extra check-ins '
                      'are optional.'
                : 'Meet this minimum on any days in the week. Once it is '
                      'reached, the rest of the week is optional.',
            muted: true,
          ),
          Counter(
            value: _countOf(pace),
            min: 1,
            max: pace is MonthlyPace ? 31 : 7,
            onChanged: (count) => setState(() {
              _error = '';
              _pace = pace is MonthlyPace
                  ? MonthlyPace(count)
                  : WeeklyPace(count);
            }),
          ),
          Label(
            pace is MonthlyPace ? 'days a month' : 'times a week',
            muted: true,
            align: TextAlign.center,
          ),
        ],
        if (_error.isNotEmpty) ErrorNote(_error),
        LockButton(
          title: pace is CustomPace ? 'APPLY SCHEDULE' : 'APPLY TARGET',
          onPressed: _apply,
        ),
      ],
    );
  }

  int _countOf(Pace p) => switch (p) {
    DailyPace(:final count) => count,
    WeeklyPace(:final count) => count,
    CustomPace(:final days) => days.length,
    MonthlyPace(:final count) => count,
    WindowPace(:final targetCount) => targetCount,
  };
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
    semanticLabel: label,
    selected: selected,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 38),
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.inkPrimary : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Label(
        label,
        size: 11,
        color: selected ? AppColors.onDark : AppColors.inkPrimary,
      ),
    ),
  );
}
