/// The "hard shadow" look of the design.
///
/// The reference screens do not use soft blurry shadows. Instead a solid dark
/// copy of the box sits a few pixels down and to the right of it, like a thick
/// printed edge. The React Native app faked this with an extra backing `View`;
/// here [RaisedBox] draws the backing with a [Positioned] layer in a [Stack].
///
/// A pressed button moves *towards* its backing (see `LockButton`), which is
/// why the face is a separate, translatable layer.
library;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// Draws [child] (the "face") with a solid offset backing behind it.
class RaisedBox extends StatelessWidget {
  /// Creates a raised box.
  const RaisedBox({
    super.key,
    required this.child,
    this.dx = 3,
    this.dy = 4,
    this.backingColor = AppColors.inkPrimary,
    this.borderRadius = BorderRadius.zero,
    this.faceOffset = Offset.zero,
  });

  /// The face content. It should paint its own background and border.
  final Widget child;

  /// Backing offset to the right.
  final double dx;

  /// Backing offset downwards.
  final double dy;

  /// Colour of the backing.
  final Color backingColor;

  /// Corner radius of the backing (match the face).
  final BorderRadius borderRadius;

  /// Extra translation of the face (used for the pressed state).
  final Offset faceOffset;

  @override
  Widget build(BuildContext context) {
    // Reserve room for the backing so neighbouring widgets do not overlap it.
    return Padding(
      padding: EdgeInsets.only(right: dx, bottom: dy),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: dx,
            top: dy,
            right: -dx,
            bottom: -dy,
            child: DecoratedBox(
              decoration: BoxDecoration(color: backingColor, borderRadius: borderRadius),
            ),
          ),
          Transform.translate(offset: faceOffset, child: child),
        ],
      ),
    );
  }
}
