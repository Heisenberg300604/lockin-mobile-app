/// The status pill shown on cards and detail screens.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/feather_icons.dart';
import '../../../../core/widgets/typography.dart';
import '../../domain/models.dart';

/// A pill showing a commitment's status (Active, Paused, Broken, Completed).
/// The text is always shown, never colour alone.
class StatusChip extends StatelessWidget {
  /// Creates a chip.
  const StatusChip(this.status, {super.key});

  /// Status to show.
  final CommitmentStatus status;

  @override
  Widget build(BuildContext context) {
    final positive = status == CommitmentStatus.active || status == CommitmentStatus.completed;
    final broken = status == CommitmentStatus.broken;
    final background = positive
        ? AppColors.successBackground
        : broken
            ? AppColors.dangerBackground
            : AppColors.surfacePanel;
    final foreground = positive
        ? AppColors.successForeground
        : broken
            ? AppColors.dangerForeground
            : AppColors.inkSecondary;
    final icon = switch (status) {
      CommitmentStatus.paused => Feather.pauseCircle,
      CommitmentStatus.broken => Feather.xCircle,
      CommitmentStatus.completed => Feather.checkCircle,
      CommitmentStatus.active => Feather.circle,
    };
    return StateMotion(
      value: status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(30)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            AppIcon(icon, size: 11, color: foreground),
            Label(status.name, size: 11, color: foreground, capitalize: true),
          ],
        ),
      ),
    );
  }
}

