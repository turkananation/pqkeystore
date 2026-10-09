// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Tests for canonicalAad stability.
// No secret material in test output.

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

void main() {
  group('canonicalAad', () {
    KeyMetadata testMeta({String id = 'aad-test-key'}) => KeyMetadata(
      id: KeyId(id),
      kind: KeyKind.mlKemSecret,
      algorithm: 'ML-KEM-768',
      createdAt: DateTime.utc(2025, 1, 1, 12, 0, 0),
      purpose: 'testing',
      tags: {'env': 'test', 'tier': 'alpha'},
    );

    test('produces identical output for identical metadata', () {
      final meta = testMeta();
      final aad1 = canonicalAad(meta);
      final aad2 = canonicalAad(meta);

      expect(aad1, equals(aad2));
    });

    test(
      'produces identical output across separate instances with same data',
      () {
        final meta1 = testMeta();
        final meta2 = testMeta();

        expect(canonicalAad(meta1), equals(canonicalAad(meta2)));
      },
    );

    test('produces different output for different metadata', () {
      final meta1 = testMeta(id: 'key-alpha');
      final meta2 = testMeta(id: 'key-bravo');

      expect(canonicalAad(meta1), isNot(equals(canonicalAad(meta2))));
    });

    test('output is non-empty', () {
      final aad = canonicalAad(testMeta());
      expect(aad.isNotEmpty, isTrue);
    });

    test('tag ordering does not affect output', () {
      final meta1 = KeyMetadata(
        id: const KeyId('order-test'),
        kind: KeyKind.classicalEd25519,
        algorithm: 'Ed25519',
        createdAt: DateTime.utc(2025, 6, 1),
        tags: {'b': '2', 'a': '1'},
      );
      final meta2 = KeyMetadata(
        id: const KeyId('order-test'),
        kind: KeyKind.classicalEd25519,
        algorithm: 'Ed25519',
        createdAt: DateTime.utc(2025, 6, 1),
        tags: {'a': '1', 'b': '2'},
      );

      expect(canonicalAad(meta1), equals(canonicalAad(meta2)));
    });
  });
}
