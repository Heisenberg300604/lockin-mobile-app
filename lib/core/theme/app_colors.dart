/// Every colour used in the app, defined **once**.
///
/// The values were sampled from the original design PNGs (see `design.md` /
/// `design-tokens.json` in the React Native project), so they are exact. Use
/// these constants instead of writing hex codes in widgets: if the design ever
/// changes you edit one line here.
library;

import 'dart:ui';

/// Design colour tokens.
abstract final class AppColors {
  // --- Canvases (screen backgrounds) --------------------------------------
  /// Auth, setup wizard and reflection screens.
  static const canvasSetup = Color(0xFFF4EFE6);

  /// Dashboard, detail and logging screens.
  static const canvasFocus = Color(0xFFF4F1EA);

  // --- Surfaces -------------------------------------------------------------
  /// Large setup / calendar panels.
  static const surfacePanel = Color(0xFFFAF7F2);

  /// Tracking rows.
  static const surfaceTracking = Color(0xFFFAF6F0);

  /// Commitment, timeline and reward cards.
  static const surfaceCard = Color(0xFFE6E1DA);

  /// Dashboard greeting card and filter chips.
  static const surfaceHero = Color(0xFFC9C4BB);

  /// Input fields and choice cards.
  static const surfaceInput = Color(0xFFFFFFFF);

  // --- Ink (text and strong lines) -------------------------------------------
  /// Main text and the primary button fill.
  static const inkPrimary = Color(0xFF251F1A);

  /// Darker text used on the dashboard and detail screens.
  static const inkFocus = Color(0xFF0D0805);

  /// Supporting text.
  static const inkSecondary = Color(0xFF4D4540);

  /// Quiet, non-essential text.
  static const inkMuted = Color(0xFF807C77);

  /// Text/icons on dark fills.
  static const onDark = Color(0xFFFFFFFF);

  // --- Actions and states ------------------------------------------------------
  /// Primary button fill.
  static const actionPrimary = Color(0xFF251F1A);

  /// Selected choice-card fill.
  static const actionSelected = Color(0xFF1B1A19);

  /// Selected bottom-tab pill.
  static const accentMint = Color(0xFF6CF8BB);

  /// Progress, checkmarks, active labels.
  static const successForeground = Color(0xFF00714D);

  /// Active status chip background.
  static const successBackground = Color(0xFFA9EDCA);

  /// Broken / destructive labels.
  static const dangerForeground = Color(0xFFBA1A1A);

  /// Broken status chip background and missed calendar days.
  static const dangerBackground = Color(0xFFE9BFBB);

  /// Completed days in the calendar.
  static const calendarSuccess = Color(0xFFBBD4C7);

  // --- Lines ------------------------------------------------------------------
  /// Strong border (same as primary ink).
  static const borderStrong = Color(0xFF251F1A);

  /// Subtle border.
  static const borderSubtle = Color(0xFFE6E1DA);

  // --- One-off values from the original styles ---------------------------------
  /// Placeholder text in fields.
  static const placeholder = Color(0xFF9D9994);

  /// Border of a resting text field.
  static const fieldBorder = Color(0xFF8F8B86);

  /// Thin edge on cards (bottom/right).
  static const cardEdge = Color(0xFF9D9994);

  /// Round icon background inside an unselected choice card.
  static const choiceIconBackground = Color(0xFFF4F3F1);

  /// Description text on a selected (dark) choice card.
  static const choiceSelectedDescription = Color(0xFFE6E1DA);

  /// Count box behind the counter number.
  static const counterBox = Color(0xFFF0E1DB);

  /// Dim layer behind modal dialogs (ink at 30%).
  static const modalBackdrop = Color(0x4D251F1A);

  /// Soft shadow under pill-shaped fields and filter chips (ink at 25%).
  static const softShadow = Color(0x40251F1A);
}
