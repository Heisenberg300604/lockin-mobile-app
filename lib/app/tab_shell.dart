/// The bottom-tab shell around Focus / History / Settings.
///
/// It also hosts two app-level "effects" that must only run while someone is
/// signed in: keeping reminders in sync, and opening the right screen when a
/// reminder notification is tapped.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../core/widgets/app_icon.dart';
import '../core/widgets/feather_icons.dart';
import '../core/widgets/tappable.dart';
import '../core/widgets/typography.dart';
import '../features/commitments/application/commitments_controller.dart';
import '../features/reminders/application/reminder_providers.dart';
import '../features/reminders/data/notification_service.dart';

/// Wraps the three tab screens (`StatefulShellRoute`).
///
/// `navigationShell` is go_router's object that remembers each tab's own
/// navigation stack and scroll position, so switching tabs never resets them.
class TabShell extends ConsumerStatefulWidget {
  /// Creates the shell.
  const TabShell({super.key, required this.navigationShell});

  /// go_router's tab controller.
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<TabShell> createState() => _TabShellState();
}

class _TabShellState extends ConsumerState<TabShell> {
  StreamSubscription<ReminderTap>? _subscription;
  ReminderTap? _pendingTap;

  @override
  void initState() {
    super.initState();
    final service = ref.read(notificationServiceProvider);
    _subscription = service.taps.listen(_handleTap);
    unawaited(service.launchTap().then((tap) {
      if (tap != null) _handleTap(tap);
    }));
    // A tap can arrive before the data has loaded; open it once it has.
    ref.listenManual(commitmentsProvider.select((s) => s.loading), (_, loading) {
      if (!loading) _openPending();
    });
  }

  void _handleTap(ReminderTap tap) {
    _pendingTap = tap;
    if (!ref.read(commitmentsProvider).loading) _openPending();
  }

  void _openPending() {
    final tap = _pendingTap;
    if (tap == null || !mounted) return;
    _pendingTap = null;
    final c = ref
        .read(commitmentsProvider)
        .snapshot
        .commitments
        .where((c) => c.attemptId == tap.attemptId)
        .firstOrNull;
    if (c != null) unawaited(context.push('/commitment/${c.id}?date=${tap.date}'));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the reminder synchroniser alive while signed in.
    ref.watch(reminderSyncProvider);
    return ColoredBox(
      color: AppColors.canvasFocus,
      child: Column(
        children: [
          Expanded(child: widget.navigationShell),
          _TabBar(
            index: widget.navigationShell.currentIndex,
            onSelect: (i) {
              if (i != widget.navigationShell.currentIndex) ref.read(hapticsProvider).selection();
              widget.navigationShell.goBranch(i, initialLocation: i == widget.navigationShell.currentIndex);
            },
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _tabs = [
    ('Focus', Feather.maximize),
    ('History', Feather.rotateCcw),
    ('Settings', Feather.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Container(
      color: AppColors.canvasFocus,
      padding: EdgeInsets.only(bottom: inset > 12 ? inset : 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Tappable(
                    semanticLabel: _tabs[i].$1,
                    selected: i == index,
                    onTap: () => onSelect(i),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 76),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: i == index ? AppColors.accentMint : null,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 3,
                        children: [
                          AppIcon(_tabs[i].$2, size: 20),
                          Label(_tabs[i].$1, size: 11),
                        ],
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
