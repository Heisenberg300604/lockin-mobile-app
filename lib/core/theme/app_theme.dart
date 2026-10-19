/// The global Flutter theme.
///
/// Almost all visuals are drawn by our own widgets in `core/widgets/`, so the
/// theme mostly switches off Material defaults that would fight the design
/// (ripples, tinted surfaces) and sets the font.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

/// Builds the app's [ThemeData].
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light, // the app is light-only (see app.json)
    fontFamily: AppText.fontFamily,
    scaffoldBackgroundColor: AppColors.canvasFocus,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.inkPrimary,
      brightness: Brightness.light,
      surface: AppColors.canvasFocus,
    ),
    // The reference design has no Material ink ripples.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    // The original app slid every screen in from the right on both platforms.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
  return base.copyWith(
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.inkPrimary,
      selectionColor: Color(0x33251F1A),
      selectionHandleColor: AppColors.inkPrimary,
    ),
    // Default text colour for any Material widget we do not restyle.
    textTheme: base.textTheme.apply(
      fontFamily: AppText.fontFamily,
      bodyColor: AppColors.inkPrimary,
      displayColor: AppColors.inkPrimary,
    ),
  );
}
