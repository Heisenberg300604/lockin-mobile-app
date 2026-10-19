/// Small reusable animation widgets that follow the project's motion spec
/// (see `design.md` in the original repo) and respect "reduce motion".
///
/// Flutter does animation differently from React Native Reanimated: instead of
/// "shared values" you describe a *target* and Flutter tweens towards it
/// ("implicit animations": `AnimatedContainer`, `TweenAnimationBuilder`, ...).
/// That is why this file is much shorter than the original `motion.tsx`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reduced_motion.dart';

/// Durations from the design spec, in one place.
abstract final class Motion {
  static const press = Duration(milliseconds: 80);
  static const release = Duration(milliseconds: 120);
  static const selection = Duration(milliseconds: 140);
  static const stepEnter = Duration(milliseconds: 220);
  static const stepExit = Duration(milliseconds: 160);
  static const modalEnter = Duration(milliseconds: 200);
  static const modalExit = Duration(milliseconds: 150);
  static const progress = Duration(milliseconds: 240);
  static const listEnter = Duration(milliseconds: 200);
  static const listLayout = Duration(milliseconds: 220);
  static const state = Duration(milliseconds: 180);
  static const lock = Duration(milliseconds: 280);
  static const settle = Duration(milliseconds: 300);

  /// Very short duration used instead of movement when motion is reduced.
  static const reduced = Duration(milliseconds: 80);

  /// Returns [normal], or the short reduced duration.
  static Duration pick(bool reduce, Duration normal) => reduce ? reduced : normal;
}

/// Fades its child in when first shown. With [layout] it also animates
/// changes of its own size (used for cards whose content changes).
class MotionView extends ConsumerWidget {
  /// Creates a motion view.
  const MotionView({super.key, required this.child, this.layout = false});

  /// Content.
  final Widget child;

  /// Animate size changes.
  final bool layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = ref.watch(reducedMotionProvider);
    Widget content = child;
    if (layout && !reduced) {
      content = AnimatedSize(
        duration: Motion.listLayout,
        alignment: Alignment.topCenter,
        child: content,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.pick(reduced, Motion.listEnter),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: content,
    );
  }
}

/// Briefly dips and restores the child whenever [value] changes (a status
/// crossfade or a counter "settle"). With [settle] it also scales from 97%.
///
/// If [value] changes again mid-animation, the animation restarts from the
/// beginning instead of queueing up (the spec: "retarget, don't queue").
class StateMotion extends ConsumerStatefulWidget {
  /// Creates a state motion.
  const StateMotion({
    super.key,
    required this.value,
    required this.child,
    this.settle = false,
  });

  /// Any value; a change triggers the animation.
  final Object value;

  /// Whether to scale as well as fade.
  final bool settle;

  /// Content.
  final Widget child;

  @override
  ConsumerState<StateMotion> createState() => _StateMotionState();
}

class _StateMotionState extends ConsumerState<StateMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(StateMotion old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      final reduced = ref.read(reducedMotionProvider);
      _controller.duration =
          Motion.pick(reduced, widget.settle ? Motion.settle : Motion.state);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(reducedMotionProvider);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Opacity(
          opacity: 0.5 + t * 0.5,
          child: Transform.scale(
            scale: reduced || !widget.settle ? 1 : 0.97 + t * 0.03,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Plays a one-time "lock settling" animation on first build when [enabled]
/// (used on the commitment screen right after locking).
class LockSettle extends ConsumerWidget {
  /// Creates a lock-settle wrapper.
  const LockSettle({super.key, required this.enabled, required this.child});

  /// Whether to animate at all.
  final bool enabled;

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) return child;
    final reduced = ref.watch(reducedMotionProvider);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.pick(reduced, Motion.lock),
      builder: (context, t, child) => Opacity(
        opacity: 0.5 + t * 0.5,
        child: Transform.scale(scale: reduced ? 1 : 0.97 + t * 0.03, child: child),
      ),
      child: child,
    );
  }
}
