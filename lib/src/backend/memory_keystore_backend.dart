// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// In-memory backend for structural testing and ephemeral use.
// No persistence — all data is lost when the process exits.

import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';

/// A pure-Dart in-memory backend for [PqKeystoreBackend].
///
/// Stores sealed records in a [Map]. Useful for:
/// - Unit testing without filesystem or platform dependencies
/// - Ephemeral session-only key storage
/// - Pure Dart environments (no Flutter required beyond types)
final class MemoryKeystoreBackend implements PqKeystoreBackend {
  final Map<String, SealedRecord> _store = {};

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) async {
    _store[id.value] = record;
  }

  @override
  Future<SealedRecord?> getSealed(KeyId id) async {
    return _store[id.value];
  }

  @override
  Future<bool> delete(KeyId id) async {
    return _store.remove(id.value) != null;
  }

  @override
  Future<bool> contains(KeyId id) async {
    return _store.containsKey(id.value);
  }

  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) async {
    return _store.values.where((record) {
      if (kind != null && record.metadata.kind != kind) {
        return false;
      }
      if (purpose != null && record.metadata.purpose != purpose) {
        return false;
      }
      return true;
    }).toList();
  }
}
