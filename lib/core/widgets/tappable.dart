/// A tap target without Material ripples, with proper accessibility info.
///
/// The reference design shows no ripple/ink effects, so we use a plain
/// [GestureDetector] and add the [Semantics] a screen reader needs.
library;

import 'package:flutter/widgets.dart';

/// Makes [child] tappable.
class Tappable extends StatelessWidget {
  /// Creates a tappable.
  const Tappable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.isButton = true,
    this.enabled = true,
    this.selected,
    this.onTapDown,
    this.onTapEnd,
  });

  /// Content.
  final Widget child;

  /// Called on tap; ignored when [enabled] is false.
  final VoidCallback? onTap;

  /// Text read by screen readers (defaults to the child's own text).
  final String? semanticLabel;

  /// Announce as a button.
  final bool isButton;

  /// Whether taps are accepted.
  final bool enabled;

  /// Announce a selected state (for tabs, choices, toggles).
  final bool? selected;

  /// Finger down (used for the press animation).
  final VoidCallback? onTapDown;

  /// Finger up or cancelled.
  final VoidCallback? onTapEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: isButton,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        onTapDown: enabled && onTapDown != null ? (_) => onTapDown!() : null,
        onTapUp: onTapEnd != null ? (_) => onTapEnd!() : null,
        onTapCancel: onTapEnd,
        child: child,
      ),
    );
  }
}
