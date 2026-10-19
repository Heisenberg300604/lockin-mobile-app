/// The page scaffold shared by all screens: safe areas, header, scrolling body,
/// optional pinned footer, and a centred column capped at 480px on tablets.
library;

import 'package:flutter/material.dart' show Scaffold, Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'app_icon.dart';
import 'feather_icons.dart';
import 'lock_button.dart';
import 'typography.dart';

/// The "LockIn" logo: a lock icon and the wordmark.
class Brand extends StatelessWidget {
  /// Creates the brand mark.
  const Brand({super.key});

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          AppIcon(Feather.lock, size: 19),
          Label('LockIn', size: 24, bold: true),
        ],
      );
}

/// Top bar. Either brand + profile button, or a back arrow with a label.
class AppHeader extends StatelessWidget {
  /// Creates a header.
  const AppHeader({super.key, this.back = false, this.label, this.onBack});

  /// Show a back arrow instead of the profile button.
  final bool back;

  /// Text next to the back arrow (defaults to "LockIn").
  final String? label;

  /// Custom back action (default: pop, or go home if nothing to pop).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (back)
              Row(
                spacing: 8,
                children: [
                  IconBtn(
                    icon: Feather.arrowLeft,
                    label: 'Go back',
                    onPressed: onBack ??
                        () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  label != null
                      ? Label(label!, bold: true)
                      : const Label('LockIn', size: 22, bold: true),
                ],
              )
            else
              const Brand(),
            if (!back)
              IconBtn(
                icon: Feather.user,
                label: 'Open account',
                onPressed: () => context.go('/settings'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Standard screen layout.
///
/// * [setup] picks the warmer cream background used by auth/wizard screens.
/// * [children] go in a scrolling column (unless [scroll] is false).
/// * [footer] stays pinned above the keyboard/system bar (primary actions).
/// * [gap], [padding], [mainAxisAlignment], [crossAxisAlignment] replace the
///   React Native `contentStyle` object.
class AppScreen extends StatelessWidget {
  /// Creates a screen.
  const AppScreen({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.setup = false,
    this.scroll = true,
    this.gap = 0,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  /// Body content.
  final List<Widget> children;

  /// Widget shown above the body (usually [AppHeader]).
  final Widget? header;

  /// Widget pinned below the body.
  final Widget? footer;

  /// Use the auth/setup background colour.
  final bool setup;

  /// Whether the body scrolls.
  final bool scroll;

  /// Vertical space between children.
  final double gap;

  /// Padding around the body content.
  final EdgeInsets padding;

  /// Vertical placement of children when they do not fill the screen.
  final MainAxisAlignment mainAxisAlignment;

  /// Horizontal placement of children.
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final column = Column(
      spacing: gap,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );

    final Widget body = scroll
        ? CustomScrollView(
            slivers: [
              SliverPadding(
                padding: padding,
                // Fills the screen when content is short (so we can centre it)
                // and scrolls when content is long.
                // RULE: this sliver measures its children's natural height, so
                // NOTHING inside an AppScreen may use LayoutBuilder (Flutter
                // forbids measuring it). The smoke test in test/visual guards this.
                sliver: SliverFillRemaining(hasScrollBody: false, child: column),
              ),
            ],
          )
        : Padding(padding: padding, child: column);

    return Scaffold(
      backgroundColor: setup ? AppColors.canvasSetup : AppColors.canvasFocus,
      // Lets the body shrink when the keyboard opens so nothing is hidden.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                ?header,
                Expanded(child: body),
                if (footer != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      bottomInset > 16 ? bottomInset : 16,
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] in a transparent [Material]. TextFields need a Material
/// ancestor, which dialogs do not provide by themselves.
class TransparentMaterial extends StatelessWidget {
  /// Creates the wrapper.
  const TransparentMaterial({super.key, required this.child});

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: child);
}
