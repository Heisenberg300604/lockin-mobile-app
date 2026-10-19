/// The app's buttons: [LockButton] (primary/secondary), [IconBtn].
library;

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/motion_widgets.dart';
import '../motion/reduced_motion.dart';
import '../theme/app_colors.dart';
import 'app_icon.dart';
import 'raised_box.dart';
import 'tappable.dart';
import 'typography.dart';

/// The main button.
///
/// * default (`light: false`): solid dark button, white text ("ENTER FOCUS MODE").
/// * `light: true`: white button with a hard shadow; dark when [selected]. Used
///   for secondary actions and for option chips (like "30 days").
///
/// While [loading] the label is hidden behind a spinner but still takes up its
/// space, so the button does not change size.
class LockButton extends ConsumerStatefulWidget {
  /// Creates a button.
  const LockButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.light = false,
    this.selected = false,
    this.disabled = false,
    this.loading = false,
    this.icon,
    this.semanticLabel,
  });

  /// Button text (may be empty for an icon-only button).
  final String title;

  /// Tap handler.
  final VoidCallback onPressed;

  /// Use the white "raised" style.
  final bool light;

  /// Show the selected (dark) state of a light button.
  final bool selected;

  /// Greyed-out and not tappable.
  final bool disabled;

  /// Show a spinner and ignore taps.
  final bool loading;

  /// Optional leading icon.
  final IconData? icon;

  /// Screen-reader label (defaults to [title]).
  final String? semanticLabel;

  @override
  ConsumerState<LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends ConsumerState<LockButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(reducedMotionProvider);
    final dark = !widget.light || widget.selected;
    final ink = dark ? AppColors.onDark : AppColors.inkPrimary;
    final inactive = widget.disabled || widget.loading;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [
        if (widget.icon != null) AppIcon(widget.icon!, size: 18, color: ink),
        if (widget.title.isNotEmpty)
          Flexible(
            child: Label(
              widget.title,
              size: 12,
              bold: true,
              color: ink,
              align: TextAlign.center,
              letterSpacing: widget.light ? 0 : 0.7,
            ),
          ),
      ],
    );

    // The face is the visible box. It is wrapped in an animated translation so
    // that pressing moves it 2px towards its backing.
    Widget face = AnimatedContainer(
      duration: Motion.selection,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppColors.actionPrimary : AppColors.surfaceInput,
        border: Border.all(color: AppColors.borderStrong),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: widget.loading ? 0 : 1, child: content),
          if (widget.loading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            ),
        ],
      ),
    );

    final pressOffset = _pressed && !reduced ? const Offset(2, 2) : Offset.zero;
    face = TweenAnimationBuilder<Offset>(
      tween: Tween(end: pressOffset),
      duration: reduced ? Duration.zero : (_pressed ? Motion.press : Motion.release),
      builder: (context, offset, child) => Transform.translate(offset: offset, child: child),
      child: face,
    );

    final button = Tappable(
      semanticLabel: widget.semanticLabel ?? widget.title,
      enabled: !inactive,
      selected: widget.light ? widget.selected : null,
      onTap: widget.onPressed,
      onTapDown: () => setState(() => _pressed = true),
      onTapEnd: () => setState(() => _pressed = false),
      child: widget.light ? RaisedBox(child: face) : face,
    );
    return widget.disabled ? Opacity(opacity: 0.45, child: button) : button;
  }
}

/// A 48px-tall icon-only tap target (back arrows, plus/minus, chevrons).
class IconBtn extends StatelessWidget {
  /// Creates an icon button.
  const IconBtn({super.key, required this.icon, required this.onPressed, required this.label});

  /// Glyph.
  final IconData icon;

  /// Tap handler.
  final VoidCallback onPressed;

  /// Screen-reader name, e.g. "Go back".
  final String label;

  @override
  Widget build(BuildContext context) => Tappable(
        semanticLabel: label,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 40),
          child: Center(child: AppIcon(icon)),
        ),
      );
}
