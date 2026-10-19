/// User preferences (haptics, reduced motion, reminders) and their storage.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../commitments/domain/models.dart';

/// Whether motion follows the phone's setting or is always reduced.
enum MotionPreference { system, reduced }

/// The saved preferences.
class Preferences {
  /// Creates preferences.
  const Preferences({
    required this.haptics,
    required this.motion,
    required this.reminders,
    required this.reminderTime,
  });

  /// Factory defaults (same as the original app).
  static const defaults = Preferences(
    haptics: true,
    motion: MotionPreference.system,
    reminders: false,
    reminderTime: '20:00',
  );

  /// Gentle vibration feedback.
  final bool haptics;

  /// Motion preference.
  final MotionPreference motion;

  /// Whether daily reminders are enabled.
  final bool reminders;

  /// Reminder time in 24 hour `HH:mm`.
  final String reminderTime;

  /// Returns a copy with the given fields replaced.
  Preferences copyWith({
    bool? haptics,
    MotionPreference? motion,
    bool? reminders,
    String? reminderTime,
  }) =>
      Preferences(
        haptics: haptics ?? this.haptics,
        motion: motion ?? this.motion,
        reminders: reminders ?? this.reminders,
        reminderTime: reminderTime ?? this.reminderTime,
      );

  /// JSON form.
  Map<String, dynamic> toJson() => {
        'haptics': haptics,
        'motion': motion == MotionPreference.reduced ? 'reduced' : 'system',
        'reminders': reminders,
        'reminderTime': reminderTime,
      };

  /// Reads preferences from JSON, falling back to defaults per field.
  factory Preferences.fromJson(Map<String, dynamic> json) => Preferences(
        haptics: json['haptics'] as bool? ?? defaults.haptics,
        motion: json['motion'] == 'reduced' ? MotionPreference.reduced : MotionPreference.system,
        reminders: json['reminders'] as bool? ?? defaults.reminders,
        reminderTime: json['reminderTime'] as String? ?? defaults.reminderTime,
      );
}

/// Preferences plus whether loading from disk has finished.
class PreferencesState {
  /// Creates a state.
  const PreferencesState({required this.preferences, required this.ready});

  /// Current values (defaults until [ready]).
  final Preferences preferences;

  /// False while the stored values are still being read.
  final bool ready;
}

const _storageKey = 'lockin.preferences.v1';
final _timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Loads, validates and saves [Preferences].
///
/// A `Notifier` is Riverpod's "controller": it owns a piece of state
/// ([PreferencesState]) and exposes methods to change it. Widgets watch the
/// state and call methods; they never mutate the state directly.
class PreferencesController extends Notifier<PreferencesState> {
  Future<void> _queue = Future<void>.value();
  Preferences _current = Preferences.defaults;

  @override
  PreferencesState build() {
    unawaited(_load());
    return const PreferencesState(preferences: Preferences.defaults, ready: false);
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(keyValueStoreProvider).getString(_storageKey);
      if (raw != null) {
        _current = Preferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Unreadable preferences are not worth failing for: use defaults.
    }
    if (ref.mounted) state = PreferencesState(preferences: _current, ready: true);
  }

  /// Changes one or more preferences and persists them.
  ///
  /// Throws a [LockInException] for an invalid reminder time. Calls are queued
  /// so rapid toggles are applied in order.
  Future<void> update({
    bool? haptics,
    MotionPreference? motion,
    bool? reminders,
    String? reminderTime,
  }) {
    final operation = _queue.then((_) async {
      final next = _current.copyWith(
        haptics: haptics,
        motion: motion,
        reminders: reminders,
        reminderTime: reminderTime,
      );
      if (!_timePattern.hasMatch(next.reminderTime)) {
        throw const LockInException('Use a time like 20:00 (24-hour clock).');
      }
      await ref
          .read(keyValueStoreProvider)
          .setString(_storageKey, jsonEncode(next.toJson()));
      _current = next;
      if (ref.mounted) state = PreferencesState(preferences: next, ready: true);
    });
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}

/// The user's preferences.
final preferencesProvider =
    NotifierProvider<PreferencesController, PreferencesState>(PreferencesController.new);
