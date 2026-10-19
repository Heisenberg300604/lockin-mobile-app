/// Saves the half-finished creation wizard so closing the app loses nothing.
///
/// Stored per account (`lockin.draft.<account key>`). The `requestId` is saved
/// too: re-locking a restored draft must reuse the same idempotency id, or a
/// double submit could create two commitments.
library;

import 'dart:convert';

import 'key_value_store.dart';
import '../domain/models.dart';

/// A draft plus where the user was in the wizard.
class SavedDraft {
  /// Creates a saved draft.
  const SavedDraft({required this.draft, required this.step, required this.requestId});

  /// Field values.
  final Draft draft;

  /// Wizard step (1 to 6).
  final int step;

  /// Idempotency id for the eventual "lock".
  final String requestId;
}

/// Reads and writes the [SavedDraft] for one account.
class DraftStore {
  /// Creates a store.
  const DraftStore(this._store, this._key);

  final KeyValueStore _store;
  final String _key;

  /// The saved draft, or `null` if none / unreadable.
  Future<SavedDraft?> load() async {
    final raw = await _store.getString(_key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final step = json['step'] as int;
    if (step < 1 || step > 6) return null;
    return SavedDraft(
      draft: Draft.fromJson(json['draft'] as Map<String, dynamic>),
      step: step,
      requestId: json['requestId'] as String,
    );
  }

  /// Saves [value]; throws if the device refuses.
  Future<void> save(SavedDraft value) => _store.setString(
        _key,
        jsonEncode({
          'draft': value.draft.toJson(),
          'step': value.step,
          'requestId': value.requestId,
        }),
      );

  /// Deletes the saved draft.
  Future<void> clear() => _store.remove(_key);
}
