// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Hostile Argon2id parameters must be FormatError before unwrap. The
// fixtures are not keys and are never printed.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

import 'support/stub_keystore_crypto.dart';

void main() {
  const id = KeyId('kdf-bounds');

  KeyMetadata meta() => KeyMetadata(
    id: id,
    kind: KeyKind.mlKemSecret,
    algorithm: 'ML-KEM-768',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  Future<
    ({_SpyCrypto crypto, PqKeystore keystore, MemoryKeystoreBackend backend})
  >
  plant(Map<String, dynamic> kdfParams) async {
    final backend = MemoryKeystoreBackend();
    final crypto = _SpyCrypto(StubKeystoreCrypto());
    final keystore = PqKeystore(backend: backend, crypto: crypto);
    final metadata = meta();
    await backend.putSealed(
      id,
      SealedRecord(
        metadata: metadata,
        wrapAlg: PqForgeKeystoreCrypto.wrapAlgId,
        ciphertext: Uint8List(16),
        aad: canonicalAad(metadata),
        nonce: Uint8List(12),
        kdfParams: kdfParams,
      ),
    );
    return (crypto: crypto, keystore: keystore, backend: backend);
  }

  Map<String, dynamic> params({
    int iterations = 1,
    int memoryPowerOf2 = 10,
    int lanes = 1,
    int saltBytes = 16,
  }) => <String, dynamic>{
    'kdf': 'argon2id',
    'aead': 'aes-256-gcm',
    'salt': base64Encode(Uint8List(saltBytes)),
    'iterations': iterations,
    'memoryPowerOf2': memoryPowerOf2,
    'lanes': lanes,
  };

  Future<void> expectRefused(
    Map<String, dynamic> kdfParams,
    List<String> fragments,
  ) async {
    final planted = await plant(kdfParams);
    final result = await planted.keystore.use(
      id,
      PassphraseUnlock(Uint8List.fromList(utf8.encode('test-only'))),
      (_) async => 0,
    );
    expect(result, isA<KsFailure<int>>());
    final error = (result as KsFailure<int>).error;
    expect(error, isA<FormatError>());
    final message = error.toString();
    for (final fragment in fragments) {
      expect(message, contains(fragment));
    }
    expect(
      planted.crypto.unwraps,
      0,
      reason: 'a malformed cost must not reach unwrap',
    );
  }

  test('iterations 0 is FormatError and unwrap is not called', () async {
    await expectRefused(params(iterations: 0), <String>[
      'iterations 0',
      '1..10',
    ]);
  });

  test('memoryPowerOf2 30 is FormatError and unwrap is not called', () async {
    await expectRefused(params(memoryPowerOf2: 30), <String>[
      'memoryPowerOf2 30',
      '10..20',
    ]);
  });

  test('lanes 64 is FormatError and unwrap is not called', () async {
    await expectRefused(params(lanes: 64), <String>['lanes 64', '1..16']);
  });

  test('an 8-byte salt is FormatError even though pqforge allows 8', () async {
    await expectRefused(params(saltBytes: 8), <String>['salt length 8', '16']);
  });

  test('a non-argon2id kdf id is FormatError', () async {
    final hostile = params()..['kdf'] = 'pbkdf2-hmac-sha256';
    await expectRefused(hostile, <String>['kdf', 'argon2id']);
  });

  test('the permitted low corner still round-trips', () async {
    final backend = MemoryKeystoreBackend();
    final crypto = PqForgeKeystoreCrypto(
      iterations: 1,
      memoryPowerOf2: 10,
      lanes: 1,
    );
    final keystore = PqKeystore(backend: backend, crypto: crypto);
    final metadata = meta();
    final passphrase = PassphraseUnlock(
      Uint8List.fromList(utf8.encode('test-only-low-cost')),
    );
    final material = Uint8List.fromList(List.generate(32, (i) => i + 1));

    final stored = await keystore.put(metadata, material, passphrase);
    expect(stored, isA<KsSuccess<void>>());

    final opened = await keystore.use(id, passphrase, (plaintext) async {
      expect(plaintext, material);
      return plaintext.length;
    });
    expect((opened as KsSuccess<int>).value, 32);
  });

  test('out-of-range constructor costs are rejected before any KDF', () {
    expect(
      () => PqForgeKeystoreCrypto(memoryPowerOf2: 30),
      throwsArgumentError,
    );
    expect(() => PqForgeKeystoreCrypto(iterations: 0), throwsArgumentError);
    expect(() => PqForgeKeystoreCrypto(lanes: 64), throwsArgumentError);
  });
}

final class _SpyCrypto implements PqKeystoreCrypto {
  _SpyCrypto(this.inner);

  final PqKeystoreCrypto inner;
  int unwraps = 0;

  @override
  Future<
    ({
      Uint8List ciphertext,
      Uint8List nonce,
      String wrapAlg,
      Map<String, dynamic>? kdfParams,
    })
  >
  wrap(Uint8List plaintext, Uint8List aad, UnlockMethod unlock) =>
      inner.wrap(plaintext, aad, unlock);

  @override
  Future<Uint8List> unwrap(
    Uint8List ciphertext,
    Uint8List aad,
    Uint8List? nonce,
    String wrapAlg,
    UnlockMethod unlock, [
    Map<String, dynamic>? kdfParams,
  ]) {
    unwraps++;
    return inner.unwrap(ciphertext, aad, nonce, wrapAlg, unlock, kdfParams);
  }
}
