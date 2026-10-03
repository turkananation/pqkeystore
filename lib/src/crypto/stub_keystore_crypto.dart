// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// ╔══════════════════════════════════════════════════════════════════════╗
// ║  ██████  WARNING: NOT SECURE  ██████                               ║
// ║                                                                    ║
// ║  StubKeystoreCrypto is a trivial XOR-based stub for STRUCTURAL     ║
// ║  TESTING ONLY. It provides ZERO cryptographic security.            ║
// ║                                                                    ║
// ║  • MUST NEVER ship as production crypto.                           ║
// ║  • MUST NEVER be used with real secret material.                   ║
// ║  • Exists solely to validate backend/facade wiring without         ║
// ║    requiring pqforge or native crypto dependencies.                ║
// ║                                                                    ║
// ║  See CONTINUE.md for real crypto integration via PqForgeKeystoreCrypto. ║
// ╚══════════════════════════════════════════════════════════════════════╝

import 'dart:typed_data';

import '../api/unlock.dart';
import 'keystore_crypto.dart';

/// **NOT SECURE** — XOR-based stub for structure tests only.
///
/// This implementation:
/// - Derives a repeating key from the passphrase bytes
/// - XORs plaintext with the repeating key
/// - Stores AAD in the nonce field for verification during unwrap
/// - Uses wrap algorithm identifier `stub-xor-v1-NOT-SECURE`
///
/// **MUST NEVER** be used in production or with real secrets.
final class StubKeystoreCrypto implements PqKeystoreCrypto {
  /// The wrap algorithm identifier — clearly marked as insecure.
  static const String wrapAlgId = 'stub-xor-v1-NOT-SECURE';

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
    final keyBytes = _extractPassphrase(unlock);
    if (keyBytes.isEmpty) {
      throw StateError('StubKeystoreCrypto: passphrase must not be empty');
    }

    // XOR plaintext with repeating key
    final ciphertext = Uint8List(plaintext.length);
    for (var i = 0; i < plaintext.length; i++) {
      ciphertext[i] = plaintext[i] ^ keyBytes[i % keyBytes.length];
    }

    // Store AAD in nonce field for verification during unwrap
    final nonce = Uint8List.fromList(aad);

    return (
      ciphertext: ciphertext,
      nonce: nonce,
      wrapAlg: wrapAlgId,
      kdfParams: null,
    );
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
      throw ArgumentError('StubKeystoreCrypto: unsupported wrapAlg "$wrapAlg"');
    }

    // Verify AAD matches the nonce (which stored AAD at wrap time)
    if (nonce != null && nonce.length == aad.length) {
      for (var i = 0; i < aad.length; i++) {
        if (aad[i] != nonce[i]) {
          throw StateError('StubKeystoreCrypto: AAD verification failed');
        }
      }
    } else if (nonce != null && nonce.length != aad.length) {
      throw StateError('StubKeystoreCrypto: AAD length mismatch');
    }

    final keyBytes = _extractPassphrase(unlock);
    if (keyBytes.isEmpty) {
      throw StateError('StubKeystoreCrypto: passphrase must not be empty');
    }

    // XOR ciphertext with repeating key (same operation reverses XOR)
    final plaintext = Uint8List(ciphertext.length);
    for (var i = 0; i < ciphertext.length; i++) {
      plaintext[i] = ciphertext[i] ^ keyBytes[i % keyBytes.length];
    }

    return plaintext;
  }

  /// Extract passphrase bytes from the unlock method.
  Uint8List _extractPassphrase(UnlockMethod unlock) {
    return switch (unlock) {
      PassphraseUnlock(:final passphrase) => passphrase,
      PassphraseThenPlatform(:final passphrase) => passphrase,
      PlatformUnlock() => throw StateError(
        'StubKeystoreCrypto: PlatformUnlock not supported',
      ),
    };
  }
}
