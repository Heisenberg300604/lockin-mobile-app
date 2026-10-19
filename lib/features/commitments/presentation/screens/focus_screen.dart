/// The Focus tab: greeting, today's tracking, and the commitment lists.
///
/// States (all from the original design):
/// * loading spinner,
/// * empty account (centred "+" to create the first commitment),
/// * populated dashboard with a status filter (image 14),
/// * filtered-empty message (image 25).
library;

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/containers.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/lock_button.dart';
import '../../../../core/widgets/raised_box.dart';
import '../../../../core/widgets/status_widgets.dart';
import '../../../../core/widgets/tappable.dart';
import '../../../../core/widgets/typography.dart';
import '../../../auth/application/session_controller.dart';
import '../../application/commitments_controller.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../widgets/commitment_card.dart';
import '../widgets/log_modal.dart';
import '../widgets/section_header.dart';
import '../widgets/tracking_row.dart';

/// The default tab.
class FocusScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

/// Which status the filter chips show. `all` = active + paused + broken.
enum _Filter { all, active, paused, broken }

class _FocusScreenState extends ConsumerState<FocusScreen> {
  _Filter _filter = _Filter.active;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(commitmentsProvider);
    final identity = ref.watch(sessionProvider.select((s) => s.identity));
    final now = data.now;
    final today = dateInZone(now);
    final monday = addDays(today, -dayOfWeek(today));

    // "Current" = still in play: completed attempts live in History, and an
    // attempt that was restarted is superseded by its replacement.
    final current = data.snapshot.commitments
        .where((c) => c.status != CommitmentStatus.completed && c.restartedBy == null)
        .toList();
    final filtered = current
        .where((c) => _filter == _Filter.all || c.status.name == _filter.name)
        .toList();
    final rows = apiDueRows(data.snapshot, now);

    if (data.loading) {
      return const AppScreen(
        header: AppHeader(),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(child: CircularProgressIndicator(color: AppColors.inkPrimary)),
        ],
      );
    }

    if (current.isEmpty) {
      return AppScreen(
        header: const AppHeader(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (data.error != null)
            Notice(data.error!, onRetry: () => ref.read(commitmentsProvider.notifier).refresh()),
          SizedBox(
            width: 64,
            child: LockButton(
              title: '',
              icon: Feather.plus,
              light: true,
              semanticLabel: 'Create your first commitment',
              onPressed: () => context.push('/commitment/new'),
            ),
          ),
          const SizedBox(height: 20),
          const Label('No active commitments found.', size: 13, bold: true),
          const SizedBox(height: 4),
          const Label(
            'Tap the icon above to lock in your first target.',
            muted: true,
            align: TextAlign.center,
          ),
        ],
      );
    }

    final greeting = now.hour < 12
        ? 'Morning'
        : now.hour < 17
            ? 'Afternoon'
            : 'Evening';

    return AppScreen(
      header: const AppHeader(),
      gap: 24,
      children: [
        if (data.error != null)
          Notice(data.error!, onRetry: () => ref.read(commitmentsProvider.notifier).refresh()),
        // ---- Greeting card -------------------------------------------------
        AppCard(
          color: AppColors.surfaceHero,
          edge: const EdgeInsets.only(bottom: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 20,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Label('☼ Good $greeting,', size: 10),
                        Label(
                          (identity?.name.isNotEmpty ?? false) ? identity!.name : 'Your next chapter',
                          size: 16,
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                  _WeekStrip(monday: monday, today: today),
                ],
              ),
              _NewCommitmentButton(onTap: () => context.push('/commitment/new')),
            ],
          ),
        ),
        // ---- Today's tracking ----------------------------------------------
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            SectionHeader(title: "Today's Tracking", onViewAll: () => context.push('/tracking')),
            if (rows.isNotEmpty)
              for (final row in rows.take(4))
                TrackingRow(
                  key: ValueKey('${row.commitment.id}${row.date}'),
                  commitment: row.commitment,
                  date: row.date,
                  catchUp: row.catchUp,
                  onPressed: () => showLogModal(context, LogSelection(row.commitment, row.date)),
                )
            else
              const Label('No commitments due today.', size: 13, muted: true),
          ],
        ),
        // ---- Filter chips ---------------------------------------------------
        Row(
          spacing: 10,
          children: [
            for (final value in _Filter.values)
              Expanded(
                child: _FilterChip(
                  label: value.name,
                  selected: _filter == value,
                  onTap: () {
                    if (_filter != value) ref.read(hapticsProvider).selection();
                    setState(() => _filter = value);
                  },
                ),
              ),
          ],
        ),
        // ---- Lists -----------------------------------------------------------
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Label(
              'No ${_filter == _Filter.all ? 'current' : _filter.name} commitments found.',
              size: 13,
              align: TextAlign.center,
            ),
          )
        else
          for (final path in HabitPath.values)
            if (filtered.any((c) => c.path == path))
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  SectionHeader(
                    title: path == HabitPath.build ? 'Building Habits' : 'Quitting Habits',
                    onViewAll: () => context.push('/commitments?path=${path.name}&status=${_filter.name}'),
                  ),
                  for (final c in filtered.where((c) => c.path == path).take(3))
                    CommitmentCard(key: ValueKey(c.id), commitment: c),
                ],
              ),
      ],
    );
  }
}

/// Monday-to-Sunday date strip; tapping a day opens it in History.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.monday, required this.today});

  final String monday;
  final String today;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (context) {
              final date = addDays(monday, i);
              final active = date == today;
              return Tappable(
                semanticLabel: 'History for $date',
                onTap: () => context.go('/history?date=$date'),
                child: SizedBox(
                  width: 23,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      spacing: 7,
                      children: [
                        Label(weekdayNames[i][0], size: 9, muted: true),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: active ? AppColors.inkPrimary : null,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Label(
                            '${int.parse(date.substring(8))}',
                            size: 10,
                            color: active ? AppColors.onDark : AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      );
}

class _NewCommitmentButton extends StatelessWidget {
  const _NewCommitmentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
        semanticLabel: 'Lock in new commitment',
        onTap: onTap,
        child: RaisedBox(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfacePanel,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  color: AppColors.inkPrimary,
                  padding: const EdgeInsets.all(10),
                  child: const AppIcon(Feather.lock, size: 20, color: AppColors.onDark),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Label('LOCK-IN NEW\nCOMMITMENT', size: 12, bold: true),
                      Label('Start a new habit matrix here', size: 10, muted: true),
                    ],
                  ),
                ),
                const AppIcon(Feather.arrowRight),
              ],
            ),
          ),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
        semanticLabel: 'Filter $label',
        selected: selected,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.inkFocus : AppColors.surfaceHero,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: Color(0x33251F1A), offset: Offset(0, 2), blurRadius: 2),
            ],
          ),
          child: Label(
            label,
            size: 12,
            capitalize: true,
            color: selected ? AppColors.onDark : AppColors.inkPrimary,
          ),
        ),
      );
}
