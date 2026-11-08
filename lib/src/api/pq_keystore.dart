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
import '../crypto/kdf_bounds.dart';
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
  /// v1 accepts only [PassphraseUnlock]. [PlatformUnlock] and
  /// [PassphraseThenPlatform] return [PolicyError] and never reach the crypto
  /// adapter. [PassphraseThenPlatform] is not treated as passphrase-only.
  ///
  /// A [KeyKind.thresholdShare] record is held to the same structural rules as
  /// [putShare], so a direct [put] cannot bypass them. It still stores one
  /// share and does not reconstruct a key.
  Future<KsResult<void>> put(
    KeyMetadata metadata,
    Uint8List plaintext,
    UnlockMethod unlock,
  ) async {
    final policy = _unlockPolicy(unlock);
    if (policy != null) {
      return KsFailure(policy);
    }
    if (metadata.kind == KeyKind.thresholdShare) {
      final problem = _shareProblem(metadata);
      if (problem != null) {
        return KsFailure(PolicyError(problem));
      }
    }
    try {
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
  /// Stored Argon2id parameters, when present, are range-checked before
  /// unwrap. An out-of-range cost is [FormatError], not [CryptoError], and
  /// the adapter is not called (ADR-0004, AGENTS.md rule 13).
  ///
  /// The plaintext buffer is zeroed after [body] completes or throws.
  /// This is the **preferred** way to access key material.
  Future<KsResult<T>> use<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List plaintext) body,
  ) {
    return _open(id, unlock, body, shareOnly: false);
  }

  /// Shared open path for [use] and [useShare].
  ///
  /// [shareOnly] refuses any record that is not one structurally valid
  /// threshold share, and it does so before unwrap. There is no path here
  /// that combines shares or reconstructs a full key.
  Future<KsResult<T>> _open<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List plaintext) body, {
    required bool shareOnly,
  }) async {
    final policy = _unlockPolicy(unlock);
    if (policy != null) {
      return KsFailure(policy);
    }
    try {
      final record = await _backend.getSealed(id);
      if (record == null) {
        return KsFailure(NotFound(id));
      }

      final identityError = _validateRecordIdentity(id, record);
      if (identityError != null) {
        return KsFailure(identityError);
      }

      if (shareOnly) {
        if (record.metadata.kind != KeyKind.thresholdShare) {
          return const KsFailure(
            PolicyError(
              'useShare requires one stored thresholdShare; '
              'this record is not a share and is not reconstructed',
            ),
          );
        }
        final problem = _shareProblem(record.metadata);
        if (problem != null) {
          return KsFailure(PolicyError('useShare: $problem'));
        }
      }

      if (record.kdfParams != null) {
        final kdfError = validateStoredArgon2idParams(
          record.kdfParams,
          saltRequired: true,
        );
        if (kdfError != null) {
          return KsFailure(kdfError);
        }
      }

      final plaintext = await _crypto.unwrap(
        record.ciphertext,
        record.aad,
        record.nonce,
        record.wrapAlg,
        unlock,
        record.kdfParams,
      );

      // SECURITY (AGENTS.md rule 10): `SecretBytes.fromUint8List` always makes
      // a copy and never takes ownership, so `plaintext` is a live secret that
      // only this scope owns. Wipe it the moment the copy exists, including
      // when the copy itself throws, or it survives in the heap until GC.
      final SecretBytes secretPlaintext;
      try {
        secretPlaintext = SecretBytes.fromUint8List(plaintext);
      } finally {
        secureZero(plaintext);
      }

      final callbackPlaintext = secretPlaintext.use(Uint8List.fromList);

      try {
        final result = await body(callbackPlaintext);
        return KsSuccess(result);
      } finally {
        secureZero(callbackPlaintext);
        secretPlaintext.dispose();
      }
    } on PqKeystoreError catch (e) {
      return KsFailure(e);
    } catch (e) {
      return KsFailure(CryptoError(e.toString()));
    }
  }

  /// v1 inner unwrap is passphrase-only.
  ///
  /// [PassphraseThenPlatform] is rejected rather than silently unwrapped with
  /// the passphrase half. Platform authentication is not an inner KDF factor
  /// in this release.
  static PolicyError? _unlockPolicy(UnlockMethod unlock) {
    return switch (unlock) {
      PassphraseUnlock() => null,
      PlatformUnlock() => const PolicyError(
        'v1 accepts only PassphraseUnlock; '
        'PlatformUnlock is not an inner unwrap factor',
      ),
      PassphraseThenPlatform() => const PolicyError(
        'v1 accepts only PassphraseUnlock; '
        'PassphraseThenPlatform is not implemented and is not treated as '
        'passphrase-only',
      ),
    };
  }

  /// Structural share rules. Returns null when [metadata] is one consistent
  /// share. Does not inspect share bytes and does not reconstruct a key.
  static String? _shareProblem(KeyMetadata metadata) {
    final threshold = metadata.threshold;
    if (threshold == null) {
      return 'ThresholdMeta must be set';
    }
    return threshold.validate();
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

  /// Store one threshold share.
  ///
  /// Structural rules, and nothing else:
  /// - [metadata.kind] must be [KeyKind.thresholdShare]
  /// - [metadata.threshold] must be non-null and [ThresholdMeta.validate]
  ///   must pass: non-empty `schemeId` and `ceremonyId`, `1 <= t <= n`,
  ///   `participantIndex` in `1..n` (1-based, matching `pqthreshold.Share.index`)
  ///
  /// Share mathematics, DKG, and full-key reconstruction belong to
  /// `pqthreshold`. This method never combines shares.
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
    final problem = _shareProblem(metadata);
    if (problem != null) {
      return KsFailure(
        PolicyError(
          problem == 'ThresholdMeta must be set'
              ? 'putShare requires ThresholdMeta to be set'
              : 'putShare: $problem',
        ),
      );
    }
    return put(metadata, shareData, unlock);
  }

  /// Unwrap one stored share and pass it to [body].
  ///
  /// Refuses a record that is not a structurally valid [KeyKind.thresholdShare]
  /// before unwrap, including a full key stored under another kind. The
  /// callback receives that one share's plaintext and no other. Cleanup
  /// matches [use]: success and thrown callbacks both wipe the buffers this
  /// package owns.
  Future<KsResult<T>> useShare<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List) body,
  ) {
    return _open<T>(id, unlock, body, shareOnly: true);
  }
}
