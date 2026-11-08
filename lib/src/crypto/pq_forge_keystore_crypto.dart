// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';
import 'package:zeroize/zeroize.dart';

import '../api/errors.dart';
import '../api/unlock.dart';
import 'kdf_bounds.dart';
import 'keystore_crypto.dart';

/// Real key wrapping via `pqforge` 0.4.x (`PqWrappedKey`, not `.pqf`/`.pqfs`).
///
/// v1 accepts only [PassphraseUnlock]. [PlatformUnlock] and
/// [PassphraseThenPlatform] are rejected here as well as at the facade; the
/// latter is not treated as passphrase-only.
///
/// Passphrase bytes are handed to pqforge as `String.fromCharCodes`, and
/// pqforge UTF-8-encodes that string before Argon2id. Bytes above 0x7F
/// therefore expand. That encoding is the v1 wire contract; it is not a raw
/// octet string. The resulting `String` cannot be wiped.
///
/// See `doc/PROVIDER_LIFECYCLE.md` for which buffers this type copies, owns,
/// and overwrites.
final class PqForgeKeystoreCrypto implements PqKeystoreCrypto {
  /// Wrap costs used when this adapter seals a new record.
  ///
  /// Defaults are pqforge's own Argon2id defaults (2 iterations, 64 MiB,
  /// 4 lanes). Tests and constrained deployments may lower them, but only
  /// inside [argon2idMinIterations]..[argon2idMaxIterations] and the matching
  /// memory and lane windows. Out-of-range costs throw [ArgumentError] at
  /// construction — a programmer error, not a malformed record.
  PqForgeKeystoreCrypto({
    this.iterations = defaultIterations,
    this.memoryPowerOf2 = defaultMemoryPowerOf2,
    this.lanes = defaultLanes,
  }) {
    final error = validateChosenArgon2idCost(
      iterations: iterations,
      memoryPowerOf2: memoryPowerOf2,
      lanes: lanes,
    );
    if (error != null) {
      throw ArgumentError(error.message);
    }
  }

  /// pqforge's published Argon2id default iteration count.
  static const int defaultIterations = 2;

  /// pqforge's published Argon2id default memory exponent (64 MiB).
  static const int defaultMemoryPowerOf2 = 16;

  /// pqforge's published Argon2id default lane count.
  static const int defaultLanes = 4;

  /// PQKS `wrapAlg` for records this adapter writes.
  static const String wrapAlgId = 'pqforge-argon2id-aes-256-gcm-v1';

  /// Invoked with a package-owned plaintext copy immediately after [secureZero].
  ///
  /// Assert-gated: release builds never call it, so setting it cannot retain a
  /// live secret. Tests use it to prove the wipe ran on the exact instance.
  /// Leave it null outside tests. This is not a custody API.
  @visibleForTesting
  static void Function(Uint8List wiped)? debugAfterPlaintextWipe;

  /// Iterations stored on records this adapter writes.
  final int iterations;

  /// `memoryPowerOf2` stored on records this adapter writes.
  final int memoryPowerOf2;

  /// Lanes stored on records this adapter writes.
  final int lanes;

  @override
  Future<
    ({
      Uint8List ciphertext,
      Uint8List nonce,
      String wrapAlg,
      Map<String, dynamic>? kdfParams,
    })
  >
  wrap(Uint8List plaintext, Uint8List aad, UnlockMethod unlock) async {
    final passphrase = _passphraseBytes(unlock);
    // `fromUint8List` copies. The caller's buffers stay caller-owned and are
    // not wiped here.
    final secretPassphrase = SecretBytes.fromUint8List(passphrase);
    final secretPlaintext = SecretBytes.fromUint8List(plaintext);
    Uint8List? exportCopy;
    Uint8List? providerCopy;
    try {
      // `use` lends the SecretBytes backing store. This function owns `copied`.
      // A direct `Uint8List.fromList` tear-off does not match
      // `T Function(Uint8List)` (its parameter is `List<int>`).
      Uint8List copyOf(Uint8List bytes) => Uint8List.fromList(bytes);
      final copied = secretPlaintext.use(copyOf);
      exportCopy = copied;
      final key = PqExportedKey(
        kind: 'pqkeystore-opaque-key',
        algorithmId: 'pqkeystore/plaintext-v1',
        bytes: copied,
        keyId: base64Encode(aad),
      );
      // PqExportedKey copies `bytes` again (pqforge 0.4.7+ `_copy`). That
      // second buffer is reachable as `key.bytes` and is dead once wrap
      // returns, because wrapKeyWithPassphrase is synchronous.
      providerCopy = key.bytes;

      final wrapped = const PqForge().wrapKeyWithPassphrase(
        key,
        secretPassphrase.use(String.fromCharCodes),
        kdf: PqKdf.argon2id,
        iterations: iterations,
        memoryPowerOf2: memoryPowerOf2,
        lanes: lanes,
      );

      return (
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        wrapAlg: wrapAlgId,
        kdfParams: <String, dynamic>{
          'kdf': wrapped.kdf,
          'aead': wrapped.aead,
          'salt': base64Encode(wrapped.salt),
          'iterations': wrapped.iterations,
          'memoryPowerOf2': wrapped.memoryPowerOf2,
          'lanes': wrapped.lanes,
          'keyKind': wrapped.keyKind,
          'algorithmId': wrapped.algorithmId,
          'keyId': wrapped.keyId ?? base64Encode(aad),
          'aad': base64Encode(aad),
        },
      );
    } on PqKeystoreError {
      rethrow;
    } on PqForgeException catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.wrap failed: $error');
    } catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.wrap failed: $error');
    } finally {
      secretPassphrase.dispose();
      secretPlaintext.dispose();
      _wipeOwned(exportCopy);
      if (providerCopy != null && !identical(providerCopy, exportCopy)) {
        _wipeOwned(providerCopy);
      }
    }
  }

  @override
  Future<Uint8List> unwrap(
    Uint8List ciphertext,
    Uint8List aad,
    Uint8List? nonce,
    String wrapAlg,
    UnlockMethod unlock, [
    Map<String, dynamic>? kdfParams,
  ]) async {
    if (wrapAlg != wrapAlgId) {
      throw const CryptoError(
        'PqForgeKeystoreCrypto: unsupported wrapAlg for pqforge integration',
      );
    }

    // Before PqWrappedKey is built and before Argon2id can allocate.
    final rejected = validateStoredArgon2idParams(
      kdfParams,
      saltRequired: true,
    );
    if (rejected != null) {
      throw rejected;
    }

    final passphrase = _passphraseBytes(unlock);
    final secretPassphrase = SecretBytes.fromUint8List(passphrase);
    try {
      final storedAad = _optionalAad(kdfParams);
      if (storedAad != null && !_bytesEqual(storedAad, aad)) {
        throw const CryptoError('PqForgeKeystoreCrypto: AAD mismatch');
      }

      final params = kdfParams!;
      final wrapped = PqWrappedKey(
        kdf: (params['kdf'] as String?) ?? PqKdf.argon2id,
        aead: (params['aead'] as String?) ?? argon2idAeadId,
        salt: base64Decode(params['salt']! as String),
        nonce: nonce ?? Uint8List(12),
        ciphertext: ciphertext,
        keyKind: (params['keyKind'] as String?) ?? 'pqkeystore-opaque-key',
        algorithmId:
            (params['algorithmId'] as String?) ?? 'pqkeystore/plaintext-v1',
        keyId: (params['keyId'] as String?) ?? base64Encode(aad),
        iterations: (params['iterations'] as int?) ?? iterations,
        memoryPowerOf2: (params['memoryPowerOf2'] as int?) ?? memoryPowerOf2,
        lanes: (params['lanes'] as int?) ?? lanes,
      );

      final restored = const PqForge().unwrapKeyWithPassphrase(
        wrapped,
        secretPassphrase.use(String.fromCharCodes),
      );
      // `restored.bytes` is pqforge's copy (PqExportedKey copies the decrypt
      // output). The caller of unwrap — the facade — owns that buffer and
      // wipes it. The decrypt temporary inside pqforge is not reachable here.
      return restored.bytes;
    } on PqKeystoreError {
      rethrow;
    } on PqForgeException catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.unwrap failed: $error');
    } catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.unwrap failed: $error');
    } finally {
      secretPassphrase.dispose();
    }
  }

  static Uint8List _passphraseBytes(UnlockMethod unlock) {
    switch (unlock) {
      case PassphraseUnlock(:final passphrase):
        if (passphrase.isEmpty) {
          throw const CryptoError(
            'PqForgeKeystoreCrypto: passphrase must not be empty',
          );
        }
        return passphrase;
      case PassphraseThenPlatform():
        throw const CryptoError(
          'PqForgeKeystoreCrypto rejects PassphraseThenPlatform; '
          'it is not a second factor and is not treated as passphrase-only',
        );
      case PlatformUnlock():
        throw const CryptoError(
          'PqForgeKeystoreCrypto requires PassphraseUnlock',
        );
    }
  }

  static Uint8List? _optionalAad(Map<String, dynamic>? kdfParams) {
    final stored = kdfParams?['aad'];
    if (stored is! String) {
      return null;
    }
    try {
      return base64Decode(stored);
    } on FormatException {
      throw const FormatError('stored aad is not valid base64');
    }
  }

  static void _wipeOwned(Uint8List? buffer) {
    if (buffer == null) {
      return;
    }
    secureZero(buffer);
    assert(() {
      debugAfterPlaintextWipe?.call(buffer);
      return true;
    }());
  }

  static bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left[i] ^ right[i];
    }
    return diff == 0;
  }
}
