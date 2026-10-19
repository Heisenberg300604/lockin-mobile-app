/// Text widgets: [Label] (body text), [ScreenTitle], [SectionLabel].
library;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// The workhorse text widget (called `Label` in the original app).
class Label extends StatelessWidget {
  /// Creates a label.
  const Label(
    this.text, {
    super.key,
    this.size = 15,
    this.bold = false,
    this.muted = false,
    this.color,
    this.align,
    this.height,
    this.letterSpacing,
    this.underline = false,
    this.uppercase = false,
    this.capitalize = false,
    this.maxLines,
    this.semanticsLabel,
  });

  /// The text.
  final String text;

  /// Font size.
  final double size;

  /// Bold (700) or regular (400).
  final bool bold;

  /// Use the quiet grey.
  final bool muted;

  /// Explicit colour (wins over [muted]).
  final Color? color;

  /// Horizontal alignment.
  final TextAlign? align;

  /// Line height multiplier (default 1.45).
  final double? height;

  /// Extra spacing between letters.
  final double? letterSpacing;

  /// Underline the text.
  final bool underline;

  /// Convert to UPPER CASE.
  final bool uppercase;

  /// Capitalise the first letter ("active" -> "Active").
  final bool capitalize;

  /// Truncate with an ellipsis after this many lines.
  final int? maxLines;

  /// Screen-reader override.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    var shown = text;
    if (uppercase) {
      shown = shown.toUpperCase();
    } else if (capitalize && shown.isNotEmpty) {
      shown = shown[0].toUpperCase() + shown.substring(1);
    }
    return Text(
      shown,
      textAlign: align,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      semanticsLabel: semanticsLabel,
      style: AppText.style(
        size: size,
        bold: bold,
        muted: muted,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        underline: underline,
      ),
    );
  }
}

/// Screen heading: 30 px bold, line height 38.
class ScreenTitle extends StatelessWidget {
  /// Creates a title.
  const ScreenTitle(this.text, {super.key, this.size = 30, this.height, this.align});

  /// The text.
  final String text;

  /// Font size (the commitment detail screen uses 38).
  final double size;

  /// Line height multiplier; default is 38 px for size 30.
  final double? height;

  /// Horizontal alignment.
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Label(
        text,
        size: size,
        bold: true,
        align: align,
        height: height ?? (size == 30 ? 38 / 30 : 40 / 38),
      );
}

/// Small spaced-out upper-case heading above a group ("TIMELINE").
class SectionLabel extends StatelessWidget {
  /// Creates a section label.
  const SectionLabel(this.text, {super.key});

  /// The text.
  final String text;

  @override
  Widget build(BuildContext context) => Label(
        text,
        size: 12,
        bold: true,
        uppercase: true,
        letterSpacing: 1.8,
        color: AppColors.inkPrimary,
      );
}
