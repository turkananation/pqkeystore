// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:zeroize/zeroize.dart';

import '../api/errors.dart';
import '../api/unlock.dart';
import 'keystore_crypto.dart';

/// Real key wrapping via `pqforge`.
///
/// Uses the pqforge passphrase key-custody flow (Argon2id → AES-256-GCM), locks
/// the metadata AAD into the wrapped key, and zeroizes temporary secret buffers.
final class PqForgeKeystoreCrypto implements PqKeystoreCrypto {
  static const String wrapAlgId = 'pqforge-argon2id-aes-256-gcm-v1';

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
    final secretPassphrase = SecretBytes.fromUint8List(passphrase);
    final secretPlaintext = SecretBytes.fromUint8List(plaintext);

    try {
      final key = PqExportedKey(
        kind: 'pqkeystore-opaque-key',
        algorithmId: 'pqkeystore/plaintext-v1',
        bytes: secretPlaintext.use(Uint8List.fromList),
        keyId: base64Encode(aad),
      );

      final wrapped = const PqForge().wrapKeyWithPassphrase(
        key,
        secretPassphrase.use(String.fromCharCodes),
        kdf: PqKdf.argon2id,
      );

      return (
        ciphertext: wrapped.ciphertext,
        nonce: wrapped.nonce,
        wrapAlg: wrapAlgId,
        kdfParams: {
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
    } on PqForgeException catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.wrap failed: $error');
    } catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.wrap failed: $error');
    } finally {
      secretPassphrase.dispose();
      secretPlaintext.dispose();
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

    final passphrase = _passphraseBytes(unlock);
    final secretPassphrase = SecretBytes.fromUint8List(passphrase);
    try {
      final storedAadBase64 = kdfParams?['aad'];
      if (storedAadBase64 is String) {
        final expectedAad = base64Decode(storedAadBase64);
        if (!_bytesEqual(expectedAad, aad)) {
          throw const CryptoError('PqForgeKeystoreCrypto: AAD mismatch');
        }
      }

      final salt = _requireBase64(kdfParams, 'salt');
      final wrapped = PqWrappedKey(
        kdf: (kdfParams?['kdf'] as String?) ?? PqKdf.argon2id,
        aead: (kdfParams?['aead'] as String?) ?? 'aes-256-gcm',
        salt: salt,
        nonce: nonce ?? Uint8List(12),
        ciphertext: ciphertext,
        keyKind: (kdfParams?['keyKind'] as String?) ?? 'pqkeystore-opaque-key',
        algorithmId:
            (kdfParams?['algorithmId'] as String?) ?? 'pqkeystore/plaintext-v1',
        keyId: (kdfParams?['keyId'] as String?) ?? base64Encode(aad),
        iterations: (kdfParams?['iterations'] as int?) ?? 2,
        memoryPowerOf2: (kdfParams?['memoryPowerOf2'] as int?) ?? 16,
        lanes: (kdfParams?['lanes'] as int?) ?? 4,
      );

      final restored = const PqForge().unwrapKeyWithPassphrase(
        wrapped,
        secretPassphrase.use(String.fromCharCodes),
      );
      return restored.bytes;
    } on PqForgeException catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.unwrap failed: $error');
    } catch (error) {
      throw CryptoError('PqForgeKeystoreCrypto.unwrap failed: $error');
    } finally {
      secretPassphrase.dispose();
    }
  }

  static Uint8List _passphraseBytes(UnlockMethod unlock) {
    final passphrase = switch (unlock) {
      PassphraseUnlock(:final passphrase) => passphrase,
      PassphraseThenPlatform(:final passphrase) => passphrase,
      PlatformUnlock() => throw const CryptoError(
        'PqForgeKeystoreCrypto requires a passphrase-based unlock',
      ),
    };
    if (passphrase.isEmpty) {
      throw const CryptoError(
        'PqForgeKeystoreCrypto: passphrase must not be empty',
      );
    }
    return passphrase;
  }

  static Uint8List _requireBase64(Map<String, dynamic>? kdfParams, String key) {
    final value = kdfParams?[key];
    if (value is! String || value.isEmpty) {
      throw const CryptoError('PqForgeKeystoreCrypto: missing KDF parameter');
    }
    return base64Decode(value);
  }

  static bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
