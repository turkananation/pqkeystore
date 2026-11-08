// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Threshold custody boundary (ADR-0005). One share in, one share out.
// No reconstruction. Test material only; nothing here is printed.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

import 'support/stub_keystore_crypto.dart';

void main() {
  late MemoryKeystoreBackend backend;
  late _SpyCrypto crypto;
  late PqKeystore keystore;

  Uint8List passphrase() =>
      Uint8List.fromList(utf8.encode('test-only-share-passphrase'));
  Uint8List shareBytes(int mark) =>
      Uint8List.fromList(List.generate(32, (i) => i == 0 ? mark : i));

  KeyMetadata shareMeta({
    String id = 'share-a',
    int t = 2,
    int n = 3,
    int participantIndex = 1,
    String ceremonyId = 'ceremony-1',
    String schemeId = 'frost-v1',
    KeyKind kind = KeyKind.thresholdShare,
    bool withThreshold = true,
  }) => KeyMetadata(
    id: KeyId(id),
    kind: kind,
    algorithm: 'FROST-Ed25519',
    createdAt: DateTime.utc(2026, 1, 1),
    threshold: withThreshold
        ? ThresholdMeta(
            schemeId: schemeId,
            t: t,
            n: n,
            participantIndex: participantIndex,
            ceremonyId: ceremonyId,
          )
        : null,
  );

  setUp(() {
    backend = MemoryKeystoreBackend();
    crypto = _SpyCrypto(StubKeystoreCrypto());
    keystore = PqKeystore(backend: backend, crypto: crypto);
  });

  bool allZero(Uint8List buffer) {
    var any = 0;
    for (var i = 0; i < buffer.length; i++) {
      any |= buffer[i];
    }
    return any == 0;
  }

  test('putShare rejects an empty schemeId before wrap', () async {
    final result = await keystore.putShare(
      shareMeta(schemeId: ''),
      shareBytes(1),
      PassphraseUnlock(passphrase()),
    );
    expect(result, isA<KsFailure<void>>());
    expect(
      ((result as KsFailure<void>).error as PolicyError).message,
      contains('schemeId'),
    );
    expect(crypto.wraps, 0);
    expect(await backend.getSealed(const KeyId('share-a')), isNull);
  });

  test('putShare rejects n below 1', () async {
    final result = await keystore.putShare(
      shareMeta(n: 0, t: 1, participantIndex: 1, id: 'share-n'),
      shareBytes(1),
      PassphraseUnlock(passphrase()),
    );
    expect(result, isA<KsFailure<void>>());
    expect(
      ((result as KsFailure<void>).error as PolicyError).message,
      contains('n must be at least 1'),
    );
    expect(crypto.wraps, 0);
  });

  test('put of an invalid share cannot bypass putShare', () async {
    final result = await keystore.put(
      shareMeta(participantIndex: 0, id: 'bypass'),
      shareBytes(1),
      PassphraseUnlock(passphrase()),
    );
    expect(result, isA<KsFailure<void>>());
    expect((result as KsFailure<void>).error, isA<PolicyError>());
    expect(crypto.wraps, 0);
    expect(await backend.getSealed(const KeyId('bypass')), isNull);
  });

  test('useShare returns that one share and no other', () async {
    final unlock = PassphraseUnlock(passphrase());
    expect(
      await keystore.putShare(
        shareMeta(id: 's1', participantIndex: 1),
        shareBytes(0x11),
        unlock,
      ),
      isA<KsSuccess<void>>(),
    );
    expect(
      await keystore.putShare(
        shareMeta(id: 's2', participantIndex: 2),
        shareBytes(0x22),
        unlock,
      ),
      isA<KsSuccess<void>>(),
    );

    final first = await keystore.useShare(const KeyId('s1'), unlock, (
      bytes,
    ) async {
      expect(bytes.length, 32);
      expect(bytes[0], 0x11);
      expect(bytes, isNot(contains(0x22)));
      return bytes[0];
    });
    expect((first as KsSuccess<int>).value, 0x11);

    final second = await keystore.useShare(const KeyId('s2'), unlock, (
      bytes,
    ) async {
      expect(bytes.length, 32);
      expect(bytes[0], 0x22);
      return bytes.length;
    });
    expect((second as KsSuccess<int>).value, 32);
  });

  test('useShare refuses a non-share and does not unwrap it', () async {
    final unlock = PassphraseUnlock(passphrase());
    final fullKey = KeyMetadata(
      id: const KeyId('full-key'),
      kind: KeyKind.mlKemSecret,
      algorithm: 'ML-KEM-768',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(
      await keystore.put(fullKey, shareBytes(0x7), unlock),
      isA<KsSuccess<void>>(),
    );
    crypto.unwraps = 0;

    final result = await keystore.useShare(
      const KeyId('full-key'),
      unlock,
      (_) async => 0,
    );
    expect(result, isA<KsFailure<int>>());
    expect((result as KsFailure<int>).error, isA<PolicyError>());
    expect(
      (result.error as PolicyError).message,
      contains('not reconstructed'),
    );
    expect(crypto.unwraps, 0);
  });

  test('useShare wipes the callback buffer when the callback throws', () async {
    final unlock = PassphraseUnlock(passphrase());
    expect(
      await keystore.putShare(shareMeta(), shareBytes(0x5), unlock),
      isA<KsSuccess<void>>(),
    );
    Uint8List? observed;
    final result = await keystore.useShare<int>(
      const KeyId('share-a'),
      unlock,
      (bytes) async {
        observed = bytes;
        throw StateError('callback failure');
      },
    );
    expect(result, isA<KsFailure<int>>());
    expect(observed, isNotNull);
    expect(allZero(observed!), isTrue);
    expect(allZero(crypto.lastUnwrap!), isTrue);
  });

  test('boundary indexes 1 and n are accepted and index n+1 is not', () async {
    final unlock = PassphraseUnlock(passphrase());
    expect(
      await keystore.putShare(
        shareMeta(id: 'lo', participantIndex: 1, n: 3),
        shareBytes(1),
        unlock,
      ),
      isA<KsSuccess<void>>(),
    );
    expect(
      await keystore.putShare(
        shareMeta(id: 'hi', participantIndex: 3, n: 3),
        shareBytes(2),
        unlock,
      ),
      isA<KsSuccess<void>>(),
    );
    final over = await keystore.putShare(
      shareMeta(id: 'over', participantIndex: 4, n: 3),
      shareBytes(3),
      unlock,
    );
    expect(over, isA<KsFailure<void>>());
    expect(crypto.wraps, 2);
  });
}

final class _SpyCrypto implements PqKeystoreCrypto {
  _SpyCrypto(this.inner);

  final PqKeystoreCrypto inner;
  int wraps = 0;
  int unwraps = 0;
  Uint8List? lastUnwrap;

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
  ]) async {
    unwraps++;
    final plaintext = await inner.unwrap(
      ciphertext,
      aad,
      nonce,
      wrapAlg,
      unlock,
      kdfParams,
    );
    lastUnwrap = plaintext;
    return plaintext;
  }
}
