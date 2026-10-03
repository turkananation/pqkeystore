// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Tests for SealedRecord PQKS binary codec.
// No secret material is used in these tests.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

void main() {
  group('SealedRecord PQKS codec', () {
    KeyMetadata testMetadata() {
      return KeyMetadata(
        id: const KeyId('test-key-001'),
        kind: KeyKind.mlKemSecret,
        algorithm: 'ML-KEM-768',
        createdAt: DateTime.utc(2025, 1, 1),
        purpose: 'unit-test',
        tags: {'env': 'test'},
      );
    }

    test('round-trip encode/decode preserves all fields', () {
      final metadata = testMetadata();
      final ciphertext = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]);
      final aad = Uint8List.fromList([0xAA, 0xDD]);
      final nonce = Uint8List.fromList([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB]);
      final kdfParams = <String, dynamic>{'iterations': 100000, 'memory': 65536};

      final record = SealedRecord(
        metadata: metadata,
        wrapAlg: 'stub-xor-v1-NOT-SECURE',
        ciphertext: ciphertext,
        aad: aad,
        nonce: nonce,
        kdfParams: kdfParams,
      );

      final encoded = record.encode();
      final decoded = SealedRecord.decode(encoded);

      expect(SealedRecord.formatVersion, equals(1));
      expect(decoded.wrapAlg, equals('stub-xor-v1-NOT-SECURE'));
      expect(decoded.ciphertext, equals(ciphertext));
      expect(decoded.aad, equals(aad));
      expect(decoded.nonce, equals(nonce));
      expect(decoded.kdfParams, equals(kdfParams));
      expect(decoded.metadata.id, equals(metadata.id));
      expect(decoded.metadata.kind, equals(KeyKind.mlKemSecret));
      expect(decoded.metadata.algorithm, equals('ML-KEM-768'));
      expect(decoded.metadata.purpose, equals('unit-test'));
      expect(decoded.metadata.tags['env'], equals('test'));
    });

    test('round-trip with null optional fields', () {
      final metadata = KeyMetadata(
        id: const KeyId('minimal-key'),
        kind: KeyKind.classicalEd25519,
        algorithm: 'Ed25519',
        createdAt: DateTime.utc(2025, 6, 15),
      );

      final record = SealedRecord(
        metadata: metadata,
        wrapAlg: 'stub-xor-v1-NOT-SECURE',
        ciphertext: Uint8List.fromList([0x42]),
        aad: Uint8List(0),
      );

      final encoded = record.encode();
      final decoded = SealedRecord.decode(encoded);

      expect(decoded.nonce, isNull);
      expect(decoded.kdfParams, isNull);
      expect(decoded.metadata.purpose, isNull);
      expect(decoded.metadata.threshold, isNull);
    });

    test('PQKS magic bytes are correct', () {
      final record = SealedRecord(
        metadata: testMetadata(),
        wrapAlg: 'test',
        ciphertext: Uint8List(1),
        aad: Uint8List(0),
      );

      final encoded = record.encode();

      // Magic: 'P' 'Q' 'K' 'S'
      expect(encoded[0], equals(0x50));
      expect(encoded[1], equals(0x51));
      expect(encoded[2], equals(0x4B));
      expect(encoded[3], equals(0x53));
    });

    test('rejects data with bad magic bytes', () {
      final badData = Uint8List.fromList([
        0xFF, 0xFF, 0xFF, 0xFF, // wrong magic
        0x00, 0x00, 0x00, 0x01, // version 1
        // ... rest doesn't matter
        0x00, 0x00, 0x00, 0x00,
      ]);

      expect(
        () => SealedRecord.decode(badData),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects data with unsupported version', () {
      final record = SealedRecord(
        metadata: testMetadata(),
        wrapAlg: 'test',
        ciphertext: Uint8List(1),
        aad: Uint8List(0),
      );

      final encoded = record.encode();

      // Tamper: set version to 99
      encoded[4] = 0x00;
      encoded[5] = 0x00;
      encoded[6] = 0x00;
      encoded[7] = 0x63; // 99

      expect(
        () => SealedRecord.decode(encoded),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects truncated data', () {
      expect(
        () => SealedRecord.decode(Uint8List.fromList([0x50, 0x51])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
