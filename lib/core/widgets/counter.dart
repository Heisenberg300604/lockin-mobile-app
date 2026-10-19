/// A "- 3 +" stepper.
library;

import 'package:flutter/widgets.dart';

import '../motion/motion_widgets.dart';
import '../theme/app_colors.dart';
import 'feather_icons.dart';
import 'lock_button.dart';
import 'typography.dart';

/// Stepper used for numeric check-ins and the "execute N times" editor.
class Counter extends StatelessWidget {
  /// Creates a counter.
  const Counter({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
  });

  /// Current number.
  final int value;

  /// Called with the new number (already clamped to [min]..[max]).
  final ValueChanged<int> onChanged;

  /// Smallest allowed value.
  final int min;

  /// Largest allowed value.
  final int max;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 24,
        children: [
          IconBtn(
            icon: Feather.minus,
            label: 'Decrease count',
            onPressed: () => onChanged(value - 1 < min ? min : value - 1),
          ),
          StateMotion(
            value: value,
            settle: true,
            child: Container(
              constraints: const BoxConstraints(minWidth: 76),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.counterBox,
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Label('$value', size: 38, bold: true),
            ),
          ),
          IconBtn(
            icon: Feather.plus,
            label: 'Increase count',
            onPressed: () => onChanged(value + 1 > max ? max : value + 1),
          ),
        ],
      );
}
