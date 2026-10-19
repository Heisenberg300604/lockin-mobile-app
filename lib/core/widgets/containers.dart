/// Layout containers from the design: [Panel], [AppCard], [AppDivider].
library;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'raised_box.dart';

/// Large cream panel with a thin border and hard shadow (setup wizard,
/// reflection).
class Panel extends StatelessWidget {
  /// Creates a panel.
  const Panel({super.key, required this.child});

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(36));
    return RaisedBox(
      dx: 2,
      dy: 4,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfacePanel,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: radius,
        ),
        child: child,
      ),
    );
  }
}

/// Grey rounded card with a thin darker edge on its bottom/right.
///
/// The edge is drawn by a slightly larger rounded rectangle behind the card
/// that peeks out 1px on the right and bottom. (Flutter cannot draw a border
/// on only two sides of a rounded box, so we layer two shapes.)
class AppCard extends StatelessWidget {
  /// Creates a card.
  const AppCard({
    super.key,
    required this.child,
    this.color = AppColors.surfaceCard,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.edge = const EdgeInsets.only(right: 1, bottom: 1),
  });

  /// Content.
  final Widget child;

  /// Fill colour.
  final Color color;

  /// Inner padding.
  final EdgeInsets padding;

  /// Corner radius.
  final double radius;

  /// How much of the darker edge shows on each side (default: right and
  /// bottom, 1px).
  final EdgeInsets edge;

  @override
  Widget build(BuildContext context) => Container(
        padding: edge,
        decoration: BoxDecoration(
          color: AppColors.cardEdge,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
          child: child,
        ),
      );
}

/// Thin horizontal rule with 16px above and below.
class AppDivider extends StatelessWidget {
  /// Creates a divider.
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(height: 1, child: ColoredBox(color: AppColors.borderSubtle)),
      );
}
