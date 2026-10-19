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
import '../../domain/models.dart';
import '../../domain/validation.dart';

/// Which editor to show.
enum PaceEditorMode { flexible, customDays }

/// Opens the pace editor. Returns the chosen [Pace], or `null` if dismissed.
///
/// [draft] provides context for validation (Quit habits may only do 1 a day).
Future<Pace?> showPaceEditor(
  BuildContext context, {
  required Draft draft,
  required PaceEditorMode mode,
}) {
  final initial = switch (mode) {
    PaceEditorMode.customDays =>
      draft.pace is CustomPace ? draft.pace : const CustomPace([0]),
    PaceEditorMode.flexible => switch (draft.pace) {
      WeeklyPace() => draft.pace,
      DailyPace(:final count) when count > 1 => draft.pace,
      _ => const WeeklyPace(3),
    },
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

  int get _maxDaily => widget.draft.path == HabitPath.quit ? 1 : 99;

  void _apply() {
    // Validate against the whole draft, filling the fields not entered yet.
    final problem = validateDraft(
      widget.draft.copyWith(
        name: widget.draft.name.isEmpty ? 'Target' : widget.draft.name,
        reward: widget.draft.reward.isEmpty ? 'Reward' : widget.draft.reward,
        pace: _pace,
      ),
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
      title: widget.mode == PaceEditorMode.customDays
          ? 'Custom Days'
          : 'Flexible Pace',
      children: [
        if (pace is CustomPace) ...[
          LockButton(
            light: true,
            title: 'Weekdays',
            onPressed: () =>
                setState(() => _pace = const CustomPace([0, 1, 2, 3, 4])),
          ),
          LockButton(
            light: true,
            title: 'Weekends',
            onPressed: () => setState(() => _pace = const CustomPace([5, 6])),
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
                    _pace = CustomPace(
                      pace.days.contains(i)
                          ? pace.days.where((d) => d != i).toList()
                          : [...pace.days, i],
                    );
                  }),
                ),
            ],
          ),
        ] else ...[
          const Label('Execute', muted: true, align: TextAlign.center),
          Counter(
            value: _countOf(pace),
            min: 1,
            max: pace is WeeklyPace ? 7 : _maxDaily,
            onChanged: (count) => setState(() {
              _pace = pace is WeeklyPace ? WeeklyPace(count) : DailyPace(count);
            }),
          ),
          const Label('times a', muted: true, align: TextAlign.center),
          Row(
            spacing: 16,
            children: [
              Expanded(
                child: LockButton(
                  light: true,
                  title: 'Week',
                  selected: pace is WeeklyPace,
                  onPressed: () => setState(() {
                    final count = _countOf(pace);
                    _pace = WeeklyPace(count > 7 ? 7 : count);
                  }),
                ),
              ),
              Expanded(
                child: LockButton(
                  light: true,
                  title: 'Day',
                  selected: pace is DailyPace,
                  onPressed: () => setState(() {
                    final count = _countOf(pace);
                    _pace = DailyPace(count > _maxDaily ? _maxDaily : count);
                  }),
                ),
              ),
            ],
          ),
        ],
        if (_error.isNotEmpty) ErrorNote(_error),
        LockButton(title: 'Apply Target', onPressed: _apply),
      ],
    );
  }

  int _countOf(Pace p) => switch (p) {
    DailyPace(:final count) => count,
    WeeklyPace(:final count) => count,
    CustomPace() => 1,
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
