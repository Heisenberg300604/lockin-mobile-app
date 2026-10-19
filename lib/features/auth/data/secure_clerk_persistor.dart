/// Stores Clerk's session data in the platform's secure storage.
///
/// Clerk's SDK keeps its session (tokens, the "client" object) between app
/// launches through a *persistor*. Its default writes plain files into the
/// app's documents folder. For a login token that is not good enough, so we
/// give it one backed by `flutter_secure_storage` instead: the iOS Keychain /
/// Android Keystore. (The React Native app did the same with expo-secure-store.)
library;

import 'dart:async';
import 'dart:convert';

import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A [clerk.Persistor] that encrypts everything at rest.
class SecureClerkPersistor implements clerk.Persistor {
  /// Creates the persistor.
  SecureClerkPersistor([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _prefix = 'lockin.clerk.';

  @override
  Future<void> initialize() async {}

  @override
  void terminate() {}

  @override
  Future<T?> read<T>(String key) async {
    final raw = await _storage.read(key: '$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T?;
    } catch (_) {
      return null; // corrupted entry: behave as if nothing was stored
    }
  }

  @override
  Future<void> write<T>(String key, T value) =>
      _storage.write(key: '$_prefix$key', value: jsonEncode(value));

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}
