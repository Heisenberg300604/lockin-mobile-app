/// Text input matching the design: a square white field with a hard shadow, or
/// a rounded "pill" variant (used on the sign-in screens).
library;

import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'raised_box.dart';
import 'status_widgets.dart';
import 'typography.dart';

/// A labelled text field.
///
/// The widget is *controlled by the parent*: it reports typing through
/// [onChanged] and displays [value]. (In Flutter you can alternatively pass a
/// `TextEditingController`; we keep the React Native style so ported screens
/// stay simple. The internal controller is synchronised with [value].)
class AppField extends StatefulWidget {
  /// Creates a field.
  const AppField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.error,
    this.pill = false,
    this.multiline = false,
    this.minHeight,
    this.maxLength,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.enabled = true,
    this.semanticLabel,
    this.textInputAction,
  });

  /// Current text.
  final String value;

  /// Called on every edit.
  final ValueChanged<String> onChanged;

  /// Label above the field.
  final String? label;

  /// Hint shown when empty.
  final String? placeholder;

  /// Error text shown below; also turns the border red.
  final String? error;

  /// Rounded variant with a soft shadow.
  final bool pill;

  /// Allow several lines (grows as you type).
  final bool multiline;

  /// Minimum height for a multiline field (default 112).
  final double? minHeight;

  /// Maximum number of characters (the counter is hidden).
  final int? maxLength;

  /// Hide the text (passwords).
  final bool obscure;

  /// Keyboard layout.
  final TextInputType? keyboardType;

  /// Autofill hints, e.g. `[AutofillHints.email]`.
  final Iterable<String>? autofillHints;

  /// Whether editing is allowed.
  final bool enabled;

  /// Screen-reader name (defaults to label/placeholder).
  final String? semanticLabel;

  /// What the keyboard's action key does.
  final TextInputAction? textInputAction;

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(AppField old) {
    super.didUpdateWidget(old);
    // Keep the controller in sync when the parent changes the value itself
    // (e.g. clearing the custom reward when a preset is chosen). Skip when it
    // already matches so the cursor does not jump while typing.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    final input = TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      obscureText: widget.obscure,
      keyboardType: widget.multiline ? TextInputType.multiline : widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      maxLines: widget.multiline ? null : 1,
      minLines: widget.multiline ? 1 : null,
      inputFormatters: [
        if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength),
      ],
      autocorrect: !widget.obscure && widget.keyboardType != TextInputType.emailAddress,
      cursorColor: AppColors.inkPrimary,
      style: AppText.style(size: 15, height: null),
      decoration: InputDecoration.collapsed(
        hintText: widget.placeholder,
        hintStyle: AppText.style(size: 15, height: null, color: AppColors.placeholder),
      ),
    );

    final Widget box = widget.pill
        ? Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.all(Radius.circular(40)),
              boxShadow: [
                BoxShadow(color: AppColors.softShadow, offset: Offset(0, 4), blurRadius: 3),
              ],
            ),
            child: input,
          )
        : RaisedBox(
            child: Container(
              constraints: BoxConstraints(
                minHeight: widget.multiline ? (widget.minHeight ?? 112) : 56,
              ),
              padding: const EdgeInsets.all(16),
              alignment: widget.multiline ? Alignment.topLeft : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                border: Border.all(
                  color: hasError ? AppColors.dangerForeground : AppColors.fieldBorder,
                ),
              ),
              child: input,
            ),
          );

    return Semantics(
      textField: true,
      label: widget.semanticLabel ?? widget.label ?? widget.placeholder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (widget.label != null)
            Label(widget.label!, size: 13, bold: true, letterSpacing: 0.4),
          box,
          if (hasError) ErrorNote(widget.error!),
        ],
      ),
    );
  }
}
