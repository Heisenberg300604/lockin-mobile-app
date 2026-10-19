/// Small generic status/feedback widgets: error text, notices, progress bars.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/motion_widgets.dart';
import '../motion/reduced_motion.dart';
import '../theme/app_colors.dart';
import 'app_icon.dart';
import 'feather_icons.dart';
import 'tappable.dart';
import 'typography.dart';

/// Red inline error message. Announced to screen readers as a live region.
class ErrorNote extends StatelessWidget {
  /// Creates an error note.
  const ErrorNote(this.message, {super.key});

  /// The message.
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Label(message, size: 13, color: AppColors.dangerForeground),
      );
}

/// A grey banner with an optional "Retry" action (load errors).
class Notice extends StatelessWidget {
  /// Creates a notice.
  const Notice(this.message, {super.key, this.onRetry});

  /// The message.
  final String message;

  /// Shows a Retry button when set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          spacing: 10,
          children: [
            Expanded(child: Label(message, size: 13)),
            if (onRetry != null)
              Tappable(
                semanticLabel: 'Retry',
                onTap: onRetry,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Label('Retry', size: 13, bold: true),
                ),
              ),
          ],
        ),
      );
}

/// Thin 3px progress bar that animates to its new value (240 ms).
class AppProgressBar extends ConsumerWidget {
  /// Creates a progress bar; [value] is 0.0 to 1.0.
  const AppProgressBar({super.key, required this.value});

  /// Fraction complete.
  final double value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = ref.watch(reducedMotionProvider);
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(clamped * 100).round()}%',
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: AppColors.surfaceInput,
          border: Border.all(color: AppColors.inkPrimary, width: 0.5),
          borderRadius: BorderRadius.circular(3),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: clamped),
          duration: reduced ? Duration.zero : Motion.progress,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: const ColoredBox(color: AppColors.successForeground),
          ),
        ),
      ),
    );
  }
}

/// "STEP 2 OF 6" with a six-segment bar for the creation wizard.
class StepProgress extends StatelessWidget {
  /// Creates a step indicator ([step] is 1 to 6).
  const StepProgress({super.key, required this.step});

  /// Current step.
  final int step;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SizedBox(
            height: 6,
            child: Row(
              spacing: 2,
              children: [
                for (var n = 1; n <= 6; n++)
                  Expanded(
                    child: StateMotion(
                      value: n <= step,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: n <= step ? AppColors.inkPrimary : AppColors.surfaceCard,
                                borderRadius: BorderRadius.circular(n == 1 || n == 6 ? 4 : 0),
                              ),
                            ),
                          ),
                          if (n == step)
                            Positioned(
                              right: -2,
                              top: -4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.inkPrimary,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.surfacePanel),
                                ),
                                child: const AppIcon(Feather.check, size: 12, color: AppColors.onDark),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Label('STEP $step OF 6', size: 11),
        ],
      );
}
