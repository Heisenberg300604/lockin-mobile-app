/// A tiny "save a string under a name" abstraction.
///
/// The local repository only needs to read and write strings, so it depends on
/// this interface rather than on `shared_preferences` directly. Tests plug in
/// an in-memory version; the app plugs in [SharedPreferencesStore].
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal asynchronous key/value storage of strings.
abstract interface class KeyValueStore {
  /// The string stored under [key], or `null`.
  Future<String?> getString(String key);

  /// Stores [value] under [key]. Throws if it could not be saved.
  Future<void> setString(String key, String value);

  /// Removes [key].
  Future<void> remove(String key);
}

/// [KeyValueStore] backed by the platform's preferences (UserDefaults on iOS,
/// SharedPreferences on Android). Fine for small JSON documents like ours.
class SharedPreferencesStore implements KeyValueStore {
  /// Creates a store on top of an initialised [SharedPreferences] instance.
  SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    final ok = await _prefs.setString(key, value);
    if (!ok) throw StateError('Could not save to device storage.');
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

/// In-memory [KeyValueStore] for tests and previews.
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  /// Synchronous read, handy in tests to inspect what was "saved".
  String? peek(String key) => _data[key];

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);
}
