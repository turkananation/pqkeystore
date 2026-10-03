// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

import 'dart:async';

import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';

/// Abstract backend interface for sealed key storage.
///
/// Backends store and retrieve [SealedRecord] blobs — they never see
/// plaintext key material. The backend is the bottom layer of the
/// pqkeystore stack:
///
/// ```
/// App → PqKeystore → Crypto (wrap/unwrap) → Backend (store/retrieve)
/// ```
///
/// Implementations:
/// - [MemoryKeystoreBackend] — in-memory, pure Dart, no persistence.
/// - [FileKeystoreBackend]   — atomic `*.pqks` files on the local filesystem.
/// - [PlatformKeystoreBackend] — OS keychain / keystore via MethodChannel.
abstract interface class PqKeystoreBackend {
  /// Store a [SealedRecord] identified by [id].
  ///
  /// If a record with the same [id] already exists it is overwritten.
  Future<void> putSealed(KeyId id, SealedRecord record);

  /// Retrieve the [SealedRecord] for [id], or `null` if not found.
  Future<SealedRecord?> getSealed(KeyId id);

  /// Delete the record identified by [id].
  ///
  /// Returns `true` if a record was deleted, `false` if [id] was not found.
  Future<bool> delete(KeyId id);

  /// Returns `true` if a record with [id] exists in this backend.
  Future<bool> contains(KeyId id);

  /// List all sealed records, optionally filtered by [kind] and/or [purpose].
  ///
  /// If both filters are provided, records must match **both**.
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose});
}
