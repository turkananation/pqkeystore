// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

import 'dart:typed_data';

import '../api/unlock.dart';

/// Abstract interface for keystore cryptographic operations.
///
/// Implementations wrap (encrypt) plaintext key material into ciphertext
/// and unwrap (decrypt) it back. The AAD (Additional Authenticated Data)
/// binds the ciphertext to its associated metadata.
///
/// Implementations:
/// - [StubKeystoreCrypto] — XOR stub, **NOT SECURE**, structure tests only.
/// - [PqForgeKeystoreCrypto] — uses pqforge with Argon2id + AES-256-GCM.
abstract interface class PqKeystoreCrypto {
  /// Wrap (encrypt) [plaintext] with the given [aad] and [unlock] method.
  ///
  /// Returns a record containing the ciphertext, nonce, wrap algorithm
  /// identifier, and any KDF metadata required to unwrap the record later.
  Future<
    ({
      Uint8List ciphertext,
      Uint8List nonce,
      String wrapAlg,
      Map<String, dynamic>? kdfParams,
    })
  >
  wrap(Uint8List plaintext, Uint8List aad, UnlockMethod unlock);

  /// Unwrap (decrypt) [ciphertext] using the provided [aad], optional [nonce],
  /// [wrapAlg] identifier, [unlock] method, and serialized KDF parameters.
  ///
  /// Returns the decrypted plaintext. The caller is responsible for zeroing
  /// the returned buffer after use.
  Future<Uint8List> unwrap(
    Uint8List ciphertext,
    Uint8List aad,
    Uint8List? nonce,
    String wrapAlg,
    UnlockMethod unlock, [
    Map<String, dynamic>? kdfParams,
  ]);
}
