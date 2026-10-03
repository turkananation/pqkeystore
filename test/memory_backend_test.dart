// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Tests for MemoryKeystoreBackend through the PqKeystore facade.
// Uses StubKeystoreCrypto (NOT SECURE — structure tests only).
// No secret material in test output.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

void main() {
  late PqKeystore keystore;
  late MemoryKeystoreBackend backend;
  late StubKeystoreCrypto crypto;

  setUp(() {
    backend = MemoryKeystoreBackend();
    crypto = StubKeystoreCrypto();
    keystore = PqKeystore(backend: backend, crypto: crypto);
  });

  Uint8List passphrase() => Uint8List.fromList(utf8.encode('test-passphrase'));
  Uint8List keyMaterial() => Uint8List.fromList(List.generate(32, (i) => i));

  KeyMetadata mlKemMeta0({String? id, String? purpose}) => KeyMetadata(
    id: KeyId(id ?? 'test-key-${DateTime.now().microsecondsSinceEpoch}'),
    kind: KeyKind.mlKemSecret,
    algorithm: 'ML-KEM-768',
    createdAt: DateTime.utc(2025, 1, 1),
    purpose: purpose,
  );

  group('PqKeystore with MemoryKeystoreBackend', () {
    test('put and use round-trip', () async {
      final meta = mlKemMeta0(id: 'roundtrip-key');
      final unlock = PassphraseUnlock(passphrase());
      final plaintext = keyMaterial();

      final putResult = await keystore.put(meta, plaintext, unlock);
      expect(putResult, isA<KsSuccess<void>>());

      final useResult = await keystore.use<List<int>>(
        const KeyId('roundtrip-key'),
        unlock,
        (pt) async => pt.toList(),
      );

      expect(useResult, isA<KsSuccess<List<int>>>());
      useResult.when(
        success: (value) {
          expect(value, equals(plaintext.toList()));
        },
        failure: (error) => fail('Expected success, got $error'),
      );
    });

    test('pqforge crypto round-trips through the keystore', () async {
      final backend = MemoryKeystoreBackend();
      final keystore = PqKeystore(
        backend: backend,
        crypto: PqForgeKeystoreCrypto(),
      );
      final plaintext = Uint8List.fromList(
        List.generate(48, (i) => (i * 13) % 251),
      );
      final unlock = PassphraseUnlock(passphrase());
      final meta = mlKemMeta0(id: 'forge-roundtrip');

      final putResult = await keystore.put(meta, plaintext, unlock);
      expect(putResult, isA<KsSuccess<void>>());

      final useResult = await keystore.use<List<int>>(
        const KeyId('forge-roundtrip'),
        unlock,
        (pt) async => pt.toList(),
      );

      expect(useResult, isA<KsSuccess<List<int>>>());
      useResult.when(
        success: (value) => expect(value, equals(plaintext.toList())),
        failure: (error) => fail('Expected success, got $error'),
      );
    });

    test('list returns stored records', () async {
      final meta1 = mlKemMeta0(id: 'list-key-1', purpose: 'signing');
      final meta2 = mlKemMeta0(id: 'list-key-2', purpose: 'encryption');
      final unlock = PassphraseUnlock(passphrase());

      await keystore.put(meta1, keyMaterial(), unlock);
      await keystore.put(meta2, keyMaterial(), unlock);

      final listResult = await keystore.list();
      expect(listResult, isA<KsSuccess<List<KeyMetadata>>>());
      listResult.when(
        success: (items) => expect(items.length, equals(2)),
        failure: (error) => fail('Expected success, got $error'),
      );
    });

    test('list filters by kind', () async {
      final mlKemMeta = KeyMetadata(
        id: const KeyId('filter-mlkem'),
        kind: KeyKind.mlKemSecret,
        algorithm: 'ML-KEM-768',
        createdAt: DateTime.utc(2025, 1, 1),
      );
      final ed25519Meta = KeyMetadata(
        id: const KeyId('filter-ed25519'),
        kind: KeyKind.classicalEd25519,
        algorithm: 'Ed25519',
        createdAt: DateTime.utc(2025, 1, 1),
      );
      final unlock = PassphraseUnlock(passphrase());

      await keystore.put(mlKemMeta, keyMaterial(), unlock);
      await keystore.put(ed25519Meta, keyMaterial(), unlock);

      final filtered = await keystore.list(kind: KeyKind.mlKemSecret);
      filtered.when(
        success: (items) {
          expect(items.length, equals(1));
          expect(items.first.kind, equals(KeyKind.mlKemSecret));
        },
        failure: (error) => fail('Expected success, got $error'),
      );
    });

    test('list filters by purpose', () async {
      final meta1 = mlKemMeta0(id: 'purpose-1', purpose: 'signing');
      final meta2 = mlKemMeta0(id: 'purpose-2', purpose: 'encryption');
      final unlock = PassphraseUnlock(passphrase());

      await keystore.put(meta1, keyMaterial(), unlock);
      await keystore.put(meta2, keyMaterial(), unlock);

      final filtered = await keystore.list(purpose: 'encryption');
      filtered.when(
        success: (items) {
          expect(items.length, equals(1));
          expect(items.first.purpose, equals('encryption'));
        },
        failure: (error) => fail('Expected success, got $error'),
      );
    });

    test('delete removes record', () async {
      final meta = mlKemMeta0(id: 'delete-key');
      final unlock = PassphraseUnlock(passphrase());

      await keystore.put(meta, keyMaterial(), unlock);
      final deleteResult = await keystore.delete(const KeyId('delete-key'));
      expect(deleteResult, isA<KsSuccess<void>>());

      final useResult = await keystore.use<void>(
        const KeyId('delete-key'),
        unlock,
        (pt) async {},
      );
      expect(useResult, isA<KsFailure<void>>());
    });

    test('use on non-existent key returns NotFound', () async {
      final unlock = PassphraseUnlock(passphrase());

      final result = await keystore.use<void>(
        const KeyId('does-not-exist'),
        unlock,
        (pt) async {},
      );

      expect(result, isA<KsFailure<void>>());
      result.when(
        success: (_) => fail('Expected failure'),
        failure: (error) => expect(error, isA<NotFound>()),
      );
    });

    test('metadata retrieves key metadata', () async {
      final meta = mlKemMeta0(id: 'metadata-key', purpose: 'test-purpose');
      final unlock = PassphraseUnlock(passphrase());

      await keystore.put(meta, keyMaterial(), unlock);

      final result = await keystore.metadata(const KeyId('metadata-key'));
      result.when(
        success: (m) {
          expect(m.id, equals(const KeyId('metadata-key')));
          expect(m.kind, equals(KeyKind.mlKemSecret));
          expect(m.purpose, equals('test-purpose'));
        },
        failure: (error) => fail('Expected success, got $error'),
      );
    });
  });

  group('PqKeystore threshold policy', () {
    test('putShare rejects non-thresholdShare kind', () async {
      final badMeta = KeyMetadata(
        id: const KeyId('bad-share'),
        kind: KeyKind.mlKemSecret, // ← wrong kind
        algorithm: 'ML-KEM-768',
        createdAt: DateTime.utc(2025, 1, 1),
        threshold: const ThresholdMeta(
          schemeId: 'frost-v1',
          t: 2,
          n: 3,
          participantIndex: 0,
          ceremonyId: 'ceremony-001',
        ),
      );
      final unlock = PassphraseUnlock(passphrase());

      final result = await keystore.putShare(badMeta, keyMaterial(), unlock);

      expect(result, isA<KsFailure<void>>());
      result.when(
        success: (_) => fail('Expected PolicyError'),
        failure: (error) => expect(error, isA<PolicyError>()),
      );
    });

    test('putShare rejects missing ThresholdMeta', () async {
      final noThresholdMeta = KeyMetadata(
        id: const KeyId('no-threshold-meta'),
        kind: KeyKind.thresholdShare,
        algorithm: 'FROST-Ed25519',
        createdAt: DateTime.utc(2025, 1, 1),
        // threshold: null ← missing
      );
      final unlock = PassphraseUnlock(passphrase());

      final result = await keystore.putShare(
        noThresholdMeta,
        keyMaterial(),
        unlock,
      );

      expect(result, isA<KsFailure<void>>());
      result.when(
        success: (_) => fail('Expected PolicyError'),
        failure: (error) => expect(error, isA<PolicyError>()),
      );
    });

    test('putShare succeeds with correct kind and ThresholdMeta', () async {
      final shareMeta = KeyMetadata(
        id: const KeyId('valid-share'),
        kind: KeyKind.thresholdShare,
        algorithm: 'FROST-Ed25519',
        createdAt: DateTime.utc(2025, 1, 1),
        threshold: const ThresholdMeta(
          schemeId: 'frost-v1',
          t: 2,
          n: 3,
          participantIndex: 1,
          ceremonyId: 'ceremony-002',
        ),
      );
      final unlock = PassphraseUnlock(passphrase());

      final result = await keystore.putShare(shareMeta, keyMaterial(), unlock);
      expect(result, isA<KsSuccess<void>>());
    });
  });

  group('PqKeystore unlock policy', () {
    test('put rejects PlatformUnlock in v1', () async {
      final meta = mlKemMeta0(id: 'platform-reject');

      final result = await keystore.put(
        meta,
        keyMaterial(),
        const PlatformUnlock(),
      );

      expect(result, isA<KsFailure<void>>());
      result.when(
        success: (_) => fail('Expected PolicyError for PlatformUnlock in v1'),
        failure: (error) => expect(error, isA<PolicyError>()),
      );
    });
  });
}
