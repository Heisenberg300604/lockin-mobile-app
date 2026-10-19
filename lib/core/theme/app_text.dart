/// Text styling. One function builds every [TextStyle] in the app so type is
/// consistent.
///
/// The original app used the Inter font at weights 400 and 700 almost
/// exclusively, with a line height of 1.45 x the font size. We keep that so
/// line wrapping matches the reference screens.
library;

import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Builds [TextStyle]s with the app's defaults.
abstract final class AppText {
  /// Font family registered in `pubspec.yaml`.
  static const fontFamily = 'Inter';

  /// The default style: Inter, line height 1.45, ink colour.
  ///
  /// * [size] – font size in logical pixels (the design scale is 38, 30, 24,
  ///   19, 15, 12; smaller sizes exist only for metadata).
  /// * [bold] – weight 700, otherwise 400.
  /// * [muted] – use the quiet grey instead of the main ink.
  /// * [color] – overrides [muted] and the default colour.
  /// * [height] – line height as a multiple of [size]; default 1.45.
  static TextStyle style({
    double size = 15,
    bool bold = false,
    bool muted = false,
    Color? color,
    double? height,
    double? letterSpacing,
    bool underline = false,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        height: height ?? 1.45,
        // "even" splits extra line spacing equally above and below the text,
        // which is how React Native / CSS lay out lines. Flutter's default
        // would nudge text slightly differently.
        leadingDistribution: TextLeadingDistribution.even,
        color: color ?? (muted ? AppColors.inkMuted : AppColors.inkPrimary),
        letterSpacing: letterSpacing,
        decoration: underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color ?? (muted ? AppColors.inkMuted : AppColors.inkPrimary),
      );
}
