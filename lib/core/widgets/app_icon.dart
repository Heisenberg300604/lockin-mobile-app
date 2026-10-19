/// Thin wrapper to draw a Feather icon at the app's default size/colour.
library;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// A Feather icon.
class AppIcon extends StatelessWidget {
  /// Creates an icon.
  const AppIcon(this.icon, {super.key, this.size = 22, this.color = AppColors.inkPrimary});

  /// Glyph from `Feather`.
  final IconData icon;

  /// Size in logical pixels.
  final double size;

  /// Colour.
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(icon, size: size, color: color),
          ),
        ),
      );
}
