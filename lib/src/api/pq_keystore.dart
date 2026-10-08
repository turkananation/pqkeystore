// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// PqKeystore facade — the primary entry point for key management.
//
// Architecture:
//   App → PqKeystore → PqKeystoreCrypto (wrap/unwrap) + PqKeystoreBackend (store/retrieve)
//
// Plaintext only exists inside use() callbacks. Buffers are zeroed in finally blocks.

import 'dart:typed_data';

import 'package:zeroize/zeroize.dart';

import '../backend/backend.dart';
import '../crypto/canonical_aad.dart';
import '../crypto/keystore_crypto.dart';
import 'errors.dart';
import 'key_id.dart';
import 'key_kind.dart';
import 'key_metadata.dart';
import 'sealed_record.dart';
import 'unlock.dart';

/// The primary API surface for the pqkeystore package.
///
/// Manages sealed key material through a [PqKeystoreBackend] and
/// [PqKeystoreCrypto] pair. Plaintext key material is only accessible
/// inside the [use] callback, and is zeroed in a `finally` block.
///
/// **Preferred usage pattern:**
/// ```dart
/// final result = await keystore.use(keyId, unlock, (plaintext) async {
///   // plaintext is available here and ONLY here
///   return doWork(plaintext);
/// });
/// ```
final class PqKeystore {
  /// Creates a new [PqKeystore] with the given [_backend] and [_crypto].
  PqKeystore({required this._backend, required this._crypto});
  final PqKeystoreBackend _backend;
  final PqKeystoreCrypto _crypto;

  /// Store key material.
  ///
  /// In format version 1, [unlock] must be [PassphraseUnlock] or
  /// [PassphraseThenPlatform]. [PlatformUnlock] alone is rejected with
  /// a [PolicyError].
  Future<KsResult<void>> put(
    KeyMetadata metadata,
    Uint8List plaintext,
    UnlockMethod unlock,
  ) async {
    try {
      // v1 policy: require passphrase-based unlock
      if (unlock is PlatformUnlock) {
        return const KsFailure(
          PolicyError('v1 requires PassphraseUnlock or PassphraseThenPlatform'),
        );
      }

      final aad = canonicalAad(metadata);
      final wrapped = await _crypto.wrap(plaintext, aad, unlock);

      final record = SealedRecord(
        metadata: metadata,
        wrapAlg: wrapped.wrapAlg,
        ciphertext: wrapped.ciphertext,
        aad: aad,
        nonce: wrapped.nonce,
        kdfParams: wrapped.kdfParams,
      );

      await _backend.putSealed(metadata.id, record);
      return const KsSuccess(null);
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(CryptoError(e.toString()));
    }
  }

  /// Retrieve and unwrap key material, passing plaintext to [body].
  ///
  /// Before the crypto adapter is called the record is re-validated: the
  /// decoded metadata ID must be the requested ID and the stored AAD must
  /// equal the canonical AAD recomputed from the decoded metadata. A record
  /// whose metadata was altered while the AAD was preserved is rejected with
  /// [FormatError] and unwrap is never invoked (ADR-0006, BUG-005).
  ///
  /// The plaintext buffer is zeroed after [body] completes or throws.
  /// This is the **preferred** way to access key material.
  Future<KsResult<T>> use<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List plaintext) body,
  ) async {
    try {
      final record = await _backend.getSealed(id);
      if (record == null) {
        return KsFailure(NotFound(id));
      }

      final identityError = _validateRecordIdentity(id, record);
      if (identityError != null) {
        return KsFailure(identityError);
      }

      final plaintext = await _crypto.unwrap(
        record.ciphertext,
        record.aad,
        record.nonce,
        record.wrapAlg,
        unlock,
        record.kdfParams,
      );
      final secretPlaintext = SecretBytes.fromUint8List(plaintext);
      final callbackPlaintext = secretPlaintext.use(Uint8List.fromList);

      try {
        final result = await body(callbackPlaintext);
        return KsSuccess(result);
      } finally {
        // Clear the callback copy before disposing the secret buffer.
        for (var i = 0; i < callbackPlaintext.length; i++) {
          callbackPlaintext[i] = 0;
        }
        secretPlaintext.dispose();
      }
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(CryptoError(e.toString()));
    }
  }

  /// Verifies that [record] is bound to [id] and that its stored AAD is the
  /// canonical encoding of its own metadata.
  ///
  /// Returns null when the record is consistent, otherwise the error to
  /// surface. This runs before any expensive or key-revealing operation so a
  /// tampered record can never reach the crypto adapter.
  static FormatError? _validateRecordIdentity(KeyId id, SealedRecord record) {
    if (record.metadata.id != id) {
      return FormatError(
        'Record ID ${record.metadata.id.value} does not match requested $id',
      );
    }
    final expectedAad = canonicalAad(record.metadata);
    if (!_bytesEqual(expectedAad, record.aad)) {
      return const FormatError(
        'Stored AAD is not the canonical encoding of the record metadata',
      );
    }
    return null;
  }

  /// Length-checked, shape-independent byte comparison.
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Delete the record identified by [id].
  Future<KsResult<void>> delete(KeyId id) async {
    try {
      final existed = await _backend.delete(id);
      if (!existed) {
        return KsFailure(NotFound(id));
      }
      return const KsSuccess(null);
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(PlatformError(e.toString()));
    }
  }

  /// List metadata for all stored keys, optionally filtered.
  Future<KsResult<List<KeyMetadata>>> list({
    KeyKind? kind,
    String? purpose,
  }) async {
    try {
      final records = await _backend.list(kind: kind, purpose: purpose);
      return KsSuccess(records.map((r) => r.metadata).toList());
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(PlatformError(e.toString()));
    }
  }

  /// Retrieve metadata for a single key without unwrapping.
  Future<KsResult<KeyMetadata>> metadata(KeyId id) async {
    try {
      final record = await _backend.getSealed(id);
      if (record == null) {
        return KsFailure(NotFound(id));
      }
      return KsSuccess(record.metadata);
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(PlatformError(e.toString()));
    }
  }

  /// Store a threshold share.
  ///
  /// Enforces policy:
  /// - [metadata.kind] must be [KeyKind.thresholdShare]
  /// - [metadata.threshold] must be non-null
  ///
  /// Threshold shares are stored individually. Full reconstruction
  /// requires explicit high-friction ceremony via `pqthreshold`.
  Future<KsResult<void>> putShare(
    KeyMetadata metadata,
    Uint8List shareData,
    UnlockMethod unlock,
  ) async {
    if (metadata.kind != KeyKind.thresholdShare) {
      return const KsFailure(
        PolicyError('putShare requires kind == KeyKind.thresholdShare'),
      );
    }
    if (metadata.threshold == null) {
      return const KsFailure(
        PolicyError('putShare requires ThresholdMeta to be set'),
      );
    }
    return put(metadata, shareData, unlock);
  }

  /// Use a threshold share — delegates to [use].
  Future<KsResult<T>> useShare<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List) body,
  ) async {
    return use<T>(id, unlock, body);
  }
}
