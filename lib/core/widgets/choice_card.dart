/// A selectable card (Build / Quit, pace options).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/motion_widgets.dart';
import '../motion/reduced_motion.dart';
import '../theme/app_colors.dart';
import '../utils/haptics.dart';
import 'app_icon.dart';
import 'raised_box.dart';
import 'tappable.dart';
import 'typography.dart';

/// White card with a hard shadow that turns dark when [selected].
///
/// Selecting animates the colour change over 140 ms and plays one light haptic
/// tick, as in the motion spec.
class ChoiceCard extends ConsumerWidget {
  /// Creates a choice card.
  const ChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.compact = false,
  });

  /// Bold heading.
  final String title;

  /// Supporting sentence.
  final String description;

  /// Leading icon.
  final IconData icon;

  /// Whether this option is the chosen one.
  final bool selected;

  /// Called when tapped.
  final VoidCallback onPressed;

  /// Smaller variant used for the pace options.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = ref.watch(reducedMotionProvider);
    final duration = reduced ? Duration.zero : Motion.selection;
    return Tappable(
      semanticLabel: title,
      selected: selected,
      onTap: () {
        ref.read(hapticsProvider).selection();
        onPressed();
      },
      child: RaisedBox(
        child: AnimatedContainer(
          duration: duration,
          constraints: BoxConstraints(minHeight: compact ? 84 : 120),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? AppColors.actionSelected : AppColors.surfaceInput,
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Row(
            spacing: 14,
            children: [
              AnimatedContainer(
                duration: duration,
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? const Color(0x00000000) : AppColors.choiceIconBackground,
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  icon,
                  color: selected ? AppColors.onDark : AppColors.inkPrimary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Label(title, bold: true, color: selected ? AppColors.onDark : null),
                    Label(
                      description,
                      size: compact ? 12 : 15,
                      color: selected ? AppColors.choiceSelectedDescription : AppColors.inkMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
