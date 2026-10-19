/// Modal dialogs in the app's visual style.
///
/// In React Native a modal is a component that is "visible" or not. In Flutter
/// the idiom is *imperative*: call [showAppModal] and `await` its result; close
/// it with `Navigator.pop(context, result)`.
///
/// ```dart
/// final confirmed = await showAppModal<bool>(
///   context,
///   builder: (context) => ModalCard(
///     title: 'Sign out?',
///     children: [ ... LockButton(onPressed: () => Navigator.pop(context, true)) ],
///   ),
/// );
/// ```
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/motion_widgets.dart';
import '../motion/reduced_motion.dart';
import '../theme/app_colors.dart';
import 'app_icon.dart';
import 'app_screen.dart';
import 'feather_icons.dart';
import 'tappable.dart';
import 'typography.dart';

/// Shows [builder]'s widget in a centred dialog with a dimmed backdrop and the
/// spec'd open/close animation (opacity + scale from 97%, 200 ms in / 150 ms out).
///
/// Dismissed by tapping outside, the system back button, or the content calling
/// `Navigator.pop`. A [ModalCard] with `busy: true` blocks dismissal.
Future<T?> showAppModal<T>(BuildContext context, {required WidgetBuilder builder}) {
  final reduced = ProviderScope.containerOf(context).read(reducedMotionProvider);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss dialog',
    barrierColor: AppColors.modalBackdrop,
    transitionDuration: Motion.pick(reduced, Motion.modalEnter),
    pageBuilder: (dialogContext, _, _) {
      final insets = MediaQuery.viewInsetsOf(dialogContext);
      return TransparentMaterial(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: builder(dialogContext),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: reduced
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                child: child,
              ),
      );
    },
  );
}

/// The visual shell of a dialog: rounded panel, title bar with a close button,
/// and scrolling content.
class ModalCard extends StatelessWidget {
  /// Creates a modal card.
  const ModalCard({
    super.key,
    required this.title,
    required this.children,
    this.busy = false,
    this.onClose,
  });

  /// Heading.
  final String title;

  /// Content, laid out in a column with 20px gaps.
  final List<Widget> children;

  /// While true the dialog cannot be dismissed (a save is in progress).
  final bool busy;

  /// Called by the X button; defaults to closing the dialog.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    const radius = 32.0;
    return PopScope(
      canPop: !busy,
      child: Semantics(
        // Tells screen readers "this is a dialog named <title>". Flutter
        // REQUIRES explicitChildNodes whenever scopesRoute is true; leaving it
        // out crashes with a failed assertion once semantics are active.
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: title,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            // 1px border on three sides and a thicker 4px edge at the bottom.
            padding: const EdgeInsets.fromLTRB(1, 1, 1, 4),
            decoration: BoxDecoration(
              color: AppColors.inkPrimary,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: ColoredBox(
                color: AppColors.canvasFocus,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          Expanded(child: Label(title, size: 20, bold: true)),
                          Tappable(
                            semanticLabel: 'Close dialog',
                            enabled: !busy,
                            onTap: onClose ?? () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.borderStrong),
                              ),
                              child: const AppIcon(Feather.x),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 20,
                          children: children,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
