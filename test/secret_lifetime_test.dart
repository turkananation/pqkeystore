// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// SECURITY REGRESSION — AGENTS.md rule 10 ("no plaintext buffer may leave a
// scope unzeroed").
//
// The defect this guards against: `SecretBytes.fromUint8List` always copies
// and never takes ownership, so the buffer returned by `PqKeystoreCrypto.unwrap`
// is a live secret owned only by the `use()` scope. Before the fix, `use()`
// copied it into a `SecretBytes` and never wiped the original, leaving key
// material in the heap until the garbage collector reclaimed it — swap, core
// dumps and post-mortem debugging could all still read it.
//
// The tests below assert on buffer *identity and contents*, never printing key
// bytes: they fail loudly if the wipe is skipped, and they use test-only
// material that is not a real key.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

/// A crypto adapter that hands back a *tracked* buffer so a test can prove the
/// facade wipes the exact instance it produced, not merely some equal buffer.
class _TrackedCrypto implements PqKeystoreCrypto {
  _TrackedCrypto(this.inner);

  final PqKeystoreCrypto inner;

  /// The last buffer handed to the facade by `unwrap`.
  Uint8List? lastUnwrapOutput;

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
  ]) async {
    final plaintext = await inner.unwrap(
      ciphertext,
      aad,
      nonce,
      wrapAlg,
      unlock,
      kdfParams,
    );
    lastUnwrapOutput = plaintext;
    return plaintext;
  }
}

KeyMetadata _meta(String id) => KeyMetadata(
  id: KeyId(id),
  kind: KeyKind.mlKemSecret,
  algorithm: 'ML-KEM-768',
  createdAt: DateTime.utc(2025, 1, 1),
);

Uint8List _passphrase() =>
    Uint8List.fromList(utf8.encode('test-only-passphrase'));

/// Test-only material. Not a key; never printed.
Uint8List _material() => Uint8List.fromList(List.generate(32, (i) => i + 1));

bool _isAllZero(Uint8List buffer) {
  var nonZero = 0;
  for (var i = 0; i < buffer.length; i++) {
    nonZero |= buffer[i];
  }
  return nonZero == 0;
}

void main() {
  late MemoryKeystoreBackend backend;
  late _TrackedCrypto crypto;
  late PqKeystore keystore;

  setUp(() {
    backend = MemoryKeystoreBackend();
    crypto = _TrackedCrypto(StubKeystoreCrypto());
    keystore = PqKeystore(backend: backend, crypto: crypto);
  });

  Future<void> seed(String id) async {
    final result = await keystore.put(
      _meta(id),
      _material(),
      PassphraseUnlock(_passphrase()),
    );
    expect(result, isA<KsSuccess<void>>());
  }

  group('AGENTS rule 10: the unwrap output buffer is wiped', () {
    test('it is zeroed after a successful use()', () async {
      await seed('wipe-success');

      final result = await keystore.use(
        const KeyId('wipe-success'),
        PassphraseUnlock(_passphrase()),
        (p) async => p.length,
      );

      expect(result, isA<KsSuccess<int>>());
      final leaked = crypto.lastUnwrapOutput;
      expect(leaked, isNotNull);
      expect(
        _isAllZero(leaked!),
        isTrue,
        reason: 'the buffer returned by unwrap must be wiped by use()',
      );
    });

    test('it is zeroed even when the callback throws', () async {
      await seed('wipe-throwing-callback');

      // Note: `use()` currently converts any exception escaping the callback
      // into `KsFailure(CryptoError)`, so the assertion is on the returned
      // failure rather than a rethrown error.
      final result = await keystore.use(
        const KeyId('wipe-throwing-callback'),
        PassphraseUnlock(_passphrase()),
        (_) async => throw StateError('callback failure'),
      );

      expect(result, isA<KsFailure<int>>());

      final leaked = crypto.lastUnwrapOutput;
      expect(leaked, isNotNull);
      expect(
        _isAllZero(leaked!),
        isTrue,
        reason: 'a throwing callback must not leave plaintext behind',
      );
    });

    test('the callback still receives real plaintext', () async {
      await seed('wipe-not-over-zeroing');

      final observed = await keystore.use(
        const KeyId('wipe-not-over-zeroing'),
        PassphraseUnlock(_passphrase()),
        (p) async {
          // Guard against a "wipe too early" regression: the callback must see
          // the genuine material, not an already-zeroed buffer.
          final nonZero = _isAllZero(p);
          expect(nonZero, isFalse);
          return p.length;
        },
      );

      expect((observed as KsSuccess<int>).value, 32);
    });

    test('the callback buffer is wiped after use() returns', () async {
      await seed('wipe-callback-copy');

      Uint8List? observed;
      await keystore.use(
        const KeyId('wipe-callback-copy'),
        PassphraseUnlock(_passphrase()),
        (p) async {
          observed = p;
          return p.length;
        },
      );

      expect(observed, isNotNull);
      expect(
        _isAllZero(observed!),
        isTrue,
        reason: 'the buffer handed to the callback must be wiped on exit',
      );
    });

    test(
      'a record that fails validation never produces an unwrap buffer',
      () async {
        await seed('wipe-not-created');
        crypto.lastUnwrapOutput = null;

        final stored = await backend.getSealed(const KeyId('wipe-not-created'));
        await backend.putSealed(
          const KeyId('wipe-not-created'),
          SealedRecord(
            metadata: _meta('wipe-not-created'),
            wrapAlg: stored!.wrapAlg,
            ciphertext: stored.ciphertext,
            aad: Uint8List.fromList([...stored.aad, 0x00]),
            nonce: stored.nonce,
            kdfParams: stored.kdfParams,
          ),
        );

        final result = await keystore.use(
          const KeyId('wipe-not-created'),
          PassphraseUnlock(_passphrase()),
          (p) async => p.length,
        );

        expect(result, isA<KsFailure<int>>());
        expect(crypto.lastUnwrapOutput, isNull);
      },
    );
  });

  group('_tracked helper sanity', () {
    test('the spy reports the buffer the facade received', () async {
      // Guards the harness itself: if the adapter stopped handing over its
      // own instance, the assertions above would pass vacuously.
      await seed('wipe-harness');
      await keystore.use(
        const KeyId('wipe-harness'),
        PassphraseUnlock(_passphrase()),
        (p) async => p.length,
      );
      expect(crypto.lastUnwrapOutput, isNotNull);
      expect(crypto.lastUnwrapOutput!.length, 32);
    });
  });
}
