/// Light touch feedback, switchable by the user in Settings.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/preferences_controller.dart';

/// Wraps Flutter's [HapticFeedback] with the user's on/off preference.
///
/// Mapping from the original Expo Haptics calls:
/// * selection → [HapticFeedback.selectionClick]
/// * success   → [HapticFeedback.mediumImpact]
/// * warning   → [HapticFeedback.heavyImpact]
class Haptics {
  /// Creates the service; [enabled] mirrors the Settings switch.
  const Haptics({required this.enabled});

  /// Whether haptics are turned on.
  final bool enabled;

  /// A tick for choosing something.
  void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Confirmation after something was saved successfully.
  void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// Restrained alert for a negative outcome.
  void warning() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}

/// Current [Haptics], rebuilt when the preference changes.
final hapticsProvider = Provider<Haptics>((ref) {
  final enabled = ref.watch(
    preferencesProvider.select((s) => s.preferences.haptics),
  );
  return Haptics(enabled: enabled);
});
