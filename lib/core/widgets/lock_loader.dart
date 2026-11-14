/// The LockIn loading screen: a padlock closing, not a spinner.
///
/// A port of the web app's `LoadingScreen` (same geometry, colours and 2.2 s
/// timing): the shackle drops and settles, the keyhole pin flashes mint, and a
/// five-segment track pulses beneath the word mark. With reduced motion on, a
/// still, closed padlock is shown instead.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/reduced_motion.dart';
import '../theme/app_colors.dart';
import 'typography.dart';

const _cycle = Duration(milliseconds: 2200);
const _trackIdle = Color(0xFFDED8CF);
const _shadow = Color(0xFFD6CBBC);

/// Full-area loader with the padlock, word mark, track and a status [label].
class LockLoader extends ConsumerStatefulWidget {
  /// Creates the loader.
  const LockLoader({super.key, this.label = 'Preparing your focus space'});

  /// Status text (an ellipsis is appended).
  final String label;

  @override
  ConsumerState<LockLoader> createState() => _LockLoaderState();
}

class _LockLoaderState extends ConsumerState<LockLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void initState() {
    super.initState();
    if (!ref.read(reducedMotionProvider)) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reducedMotionProvider, (_, reduced) {
      reduced ? _controller.stop() : _controller.repeat();
    });
    final reduced = ref.watch(reducedMotionProvider);
    return Semantics(
      liveRegion: true,
      label: '${widget.label}…',
      excludeSemantics: true,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = reduced ? 0.6 : _controller.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(72, 72 * 78 / 64),
                  painter: _PadlockPainter(t),
                ),
                const SizedBox(height: 4),
                const Label(
                  'LockIn',
                  size: 25,
                  bold: true,
                  letterSpacing: -1.2,
                ),
                if (!reduced) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 190,
                    child: Row(
                      spacing: 3,
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(child: _segment(_controller.value, i)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Label('${widget.label}…', size: 13.5),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _segment(double t, int index) {
    // Each segment runs 0.11 s behind the previous one.
    final local = (t - index * 110 / 2200) % 1.0;
    final active = _between(local, 0.08, 0.26);
    final release = _between(local, 0.52, 0.78);
    final color = Color.lerp(
      _trackIdle,
      AppColors.inkPrimary,
      active - release,
    )!;
    final grow = local < 0.26
        ? active
        : local < 0.52
        ? 1 - _between(local, 0.26, 0.52)
        : 0.0;
    return Align(
      child: Container(height: 4 * (1 + grow), color: color),
    );
  }
}

/// 0 before [a], 1 after [b], eased in between.
double _between(double t, double a, double b) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return Curves.easeInOut.transform((t - a) / (b - a));
}

class _PadlockPainter extends CustomPainter {
  const _PadlockPainter(this.t);

  /// Position in the 2.2 s cycle, 0 to 1.
  final double t;

  /// Shackle lift in SVG units (negative = raised), matching the web keyframes.
  double get _lift {
    if (t < 0.16) return -7;
    if (t < 0.40) return -7 + 7 * _between(t, 0.16, 0.40);
    if (t < 0.46) return -1.2 * _between(t, 0.40, 0.46);
    if (t < 0.52) return -1.2 + 1.2 * _between(t, 0.46, 0.52);
    if (t < 0.84) return 0;
    return -7 * _between(t, 0.84, 1.0);
  }

  Color get _pin {
    if (t < 0.34) return AppColors.canvasFocus;
    if (t < 0.43) {
      return Color.lerp(
        AppColors.canvasFocus,
        AppColors.accentMint,
        _between(t, 0.34, 0.43),
      )!;
    }
    if (t < 0.72) {
      return Color.lerp(
        AppColors.accentMint,
        AppColors.canvasFocus,
        _between(t, 0.43, 0.72),
      )!;
    }
    return AppColors.canvasFocus;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64);

    final shadow = Paint()..color = _shadow;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13.5, 37.5, 44, 34),
        const Radius.circular(4),
      ),
      shadow,
    );

    final shackle = Paint()
      ..color = AppColors.inkPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final lift = _lift;
    final path = Path()
      ..moveTo(21, 36 + lift)
      ..lineTo(21, 23 + lift)
      ..arcTo(Rect.fromLTWH(21, 12 + lift, 22, 22), math.pi, math.pi, false)
      ..lineTo(43, 36 + lift);
    canvas.drawPath(path, shackle);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 34, 44, 34),
        const Radius.circular(4),
      ),
      Paint()..color = AppColors.inkPrimary,
    );
    canvas.drawCircle(const Offset(32, 47), 4, Paint()..color = _pin);
    canvas.drawLine(
      const Offset(32, 50.5),
      const Offset(32, 56.5),
      Paint()
        ..color = AppColors.canvasFocus
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadlockPainter old) => old.t != t;
}
