/// "Reduce motion": a combination of the phone's accessibility setting and the
/// user's own switch in Settings.
///
/// Widgets that animate read [reducedMotionProvider]; when it is `true` they
/// skip movement/scaling and use instant changes or very short fades.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/preferences_controller.dart';

/// Tracks the operating system's "Reduce Motion / Remove animations" setting
/// live (it can change while the app runs).
class SystemReducedMotion extends Notifier<bool> with WidgetsBindingObserver {
  @override
  bool build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.platformDispatcher.accessibilityFeatures.disableAnimations;
  }

  @override
  void didChangeAccessibilityFeatures() {
    state = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  }
}

/// The phone's reduce-motion setting.
final systemReducedMotionProvider =
    NotifierProvider<SystemReducedMotion, bool>(SystemReducedMotion.new);

/// `true` when motion should be minimised (system setting OR app setting).
final reducedMotionProvider = Provider<bool>((ref) {
  final system = ref.watch(systemReducedMotionProvider);
  final forced = ref.watch(
    preferencesProvider.select((s) => s.preferences.motion == MotionPreference.reduced),
  );
  return system || forced;
});

/// Tracks whether the app is in the foreground (resumed) or background.
class AppLifecycle extends Notifier<AppLifecycleState> with WidgetsBindingObserver {
  @override
  AppLifecycleState build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => this.state = state;
}

/// Foreground/background state of the app.
final appLifecycleProvider =
    NotifierProvider<AppLifecycle, AppLifecycleState>(AppLifecycle.new);
