// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// PqForgeKeystoreCrypto ownership and unlock policy. Test passphrases only.
// Assertions never print buffer contents.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

import 'support/stub_keystore_crypto.dart';

void main() {
  PqForgeKeystoreCrypto lowCost() =>
      PqForgeKeystoreCrypto(iterations: 1, memoryPowerOf2: 10, lanes: 1);

  bool allZero(Uint8List buffer) {
    var any = 0;
    for (var i = 0; i < buffer.length; i++) {
      any |= buffer[i];
    }
    return any == 0;
  }

  KeyMetadata meta(String id) => KeyMetadata(
    id: KeyId(id),
    kind: KeyKind.mlKemSecret,
    algorithm: 'ML-KEM-768',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  setUp(() => PqForgeKeystoreCrypto.debugAfterPlaintextWipe = null);
  tearDown(() => PqForgeKeystoreCrypto.debugAfterPlaintextWipe = null);

  test(
    'package-owned wrap copies are wiped and the caller buffer is not',
    () async {
      final wiped = <Uint8List>[];
      PqForgeKeystoreCrypto.debugAfterPlaintextWipe = wiped.add;
      final caller = Uint8List.fromList(List.generate(32, (i) => i + 3));
      final snapshot = Uint8List.fromList(caller);
      final keystore = PqKeystore(
        backend: MemoryKeystoreBackend(),
        crypto: lowCost(),
      );
      final stored = await keystore.put(
        meta('owned-copies'),
        caller,
        PassphraseUnlock(Uint8List.fromList(utf8.encode('copy-passphrase'))),
      );
      expect(stored, isA<KsSuccess<void>>());
      expect(
        caller,
        snapshot,
        reason: 'caller-owned plaintext must not be wiped',
      );
      expect(wiped.length, 2, reason: 'export copy and PqExportedKey copy');
      for (final buffer in wiped) {
        expect(allZero(buffer), isTrue);
      }
    },
  );

  test(
    'a wrong passphrase fails closed and the error names no secret',
    () async {
      const passphraseText = 'correct-horse-test-only';
      const wrongText = 'wrong-horse-test-only';
      final keystore = PqKeystore(
        backend: MemoryKeystoreBackend(),
        crypto: lowCost(),
      );
      final unlock = PassphraseUnlock(
        Uint8List.fromList(utf8.encode(passphraseText)),
      );
      expect(
        await keystore.put(
          meta('wrong-pass'),
          Uint8List.fromList(List.generate(16, (i) => i + 1)),
          unlock,
        ),
        isA<KsSuccess<void>>(),
      );
      final result = await keystore.use(
        const KeyId('wrong-pass'),
        PassphraseUnlock(Uint8List.fromList(utf8.encode(wrongText))),
        (_) async => 0,
      );
      expect(result, isA<KsFailure<int>>());
      expect((result as KsFailure<int>).error, isA<CryptoError>());
      final message = result.error.toString();
      expect(message.contains(passphraseText), isFalse);
      expect(message.contains(wrongText), isFalse);
    },
  );

  test('bytes above 0x7F round-trip under the documented encoding', () async {
    final passphrase = Uint8List.fromList(<int>[0x63, 0xC3, 0xA9]);
    final keystore = PqKeystore(
      backend: MemoryKeystoreBackend(),
      crypto: lowCost(),
    );
    final material = Uint8List.fromList(List.generate(8, (i) => 0x80 + i));
    expect(
      await keystore.put(
        meta('high-byte'),
        material,
        PassphraseUnlock(Uint8List.fromList(passphrase)),
      ),
      isA<KsSuccess<void>>(),
    );
    final opened = await keystore.use(
      const KeyId('high-byte'),
      PassphraseUnlock(Uint8List.fromList(passphrase)),
      (plaintext) async =>
          plaintext.length == material.length && plaintext[1] == material[1],
    );
    expect((opened as KsSuccess<bool>).value, isTrue);
  });

  test('an empty passphrase is CryptoError', () async {
    final keystore = PqKeystore(
      backend: MemoryKeystoreBackend(),
      crypto: lowCost(),
    );
    final result = await keystore.put(
      meta('empty-pass'),
      Uint8List(4),
      PassphraseUnlock(Uint8List(0)),
    );
    expect(result, isA<KsFailure<void>>());
    expect((result as KsFailure<void>).error, isA<CryptoError>());
  });

  test(
    'PlatformUnlock and PassphraseThenPlatform never reach wrap or unwrap',
    () async {
      final crypto = _SpyCrypto(StubKeystoreCrypto());
      final keystore = PqKeystore(
        backend: MemoryKeystoreBackend(),
        crypto: crypto,
      );
      final material = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final platform = await keystore.put(
        meta('platform'),
        material,
        const PlatformUnlock(),
      );
      expect((platform as KsFailure<void>).error, isA<PolicyError>());

      final chained = await keystore.put(
        meta('chained'),
        material,
        PassphraseThenPlatform(Uint8List.fromList(utf8.encode('not-a-factor'))),
      );
      expect((chained as KsFailure<void>).error, isA<PolicyError>());
      expect(
        (chained.error as PolicyError).message,
        contains('not treated as passphrase-only'),
      );

      final seeded = await keystore.put(
        meta('seeded'),
        material,
        PassphraseUnlock(Uint8List.fromList(utf8.encode('seed'))),
      );
      expect(seeded, isA<KsSuccess<void>>());
      crypto.unwraps = 0;

      final used = await keystore.use(
        const KeyId('seeded'),
        const PlatformUnlock(),
        (_) async => 0,
      );
      expect((used as KsFailure<int>).error, isA<PolicyError>());
      expect(crypto.unwraps, 0);

      final chainedUse = await keystore.use(
        const KeyId('seeded'),
        PassphraseThenPlatform(Uint8List.fromList(utf8.encode('not-a-factor'))),
        (_) async => 0,
      );
      expect((chainedUse as KsFailure<int>).error, isA<PolicyError>());
      expect(crypto.unwraps, 0);
      expect(crypto.wraps, 1);
    },
  );

  test('direct unwrap of a hostile cost throws FormatError', () async {
    final crypto = lowCost();
    await expectLater(
      crypto.unwrap(
        Uint8List(16),
        Uint8List(4),
        Uint8List(12),
        PqForgeKeystoreCrypto.wrapAlgId,
        PassphraseUnlock(Uint8List.fromList(utf8.encode('x'))),
        <String, dynamic>{
          'kdf': 'argon2id',
          'salt': base64Encode(Uint8List(16)),
          'iterations': 1,
          'memoryPowerOf2': 30,
          'lanes': 1,
        },
      ),
      throwsA(isA<FormatError>()),
    );
  });
}

final class _SpyCrypto implements PqKeystoreCrypto {
  _SpyCrypto(this.inner);

  final PqKeystoreCrypto inner;
  int wraps = 0;
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
  wrap(Uint8List plaintext, Uint8List aad, UnlockMethod unlock) {
    wraps++;
    return inner.wrap(plaintext, aad, unlock);
  }

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
