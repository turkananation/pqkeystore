// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// File backend persistence and sealed-index tests.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

void main() {
  group('FileKeystoreBackend', () {
    test('persists a sealed index and keeps it in sync with deletes', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'pqkeystore-file-backend-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final backend = FileKeystoreBackend(tempDir);
      final metadata = KeyMetadata(
        id: const KeyId('persisted-key'),
        kind: KeyKind.mlKemSecret,
        algorithm: 'ML-KEM-768',
        createdAt: DateTime.utc(2025, 1, 1),
        purpose: 'persisted',
      );
      final record = SealedRecord(
        metadata: metadata,
        wrapAlg: 'pqforge-argon2id-aes-256-gcm-v1',
        ciphertext: Uint8List.fromList(utf8.encode('ciphertext')),
        aad: Uint8List.fromList(utf8.encode('aad')),
        nonce: Uint8List.fromList([1, 2, 3, 4]),
      );

      await backend.putSealed(metadata.id, record);

      final indexFile = File(
        '${tempDir.path}${Platform.pathSeparator}.pqks-index.json',
      );
      expect(indexFile.existsSync(), isTrue);

      final indexJson = indexFile.readAsStringSync();
      expect(indexJson, contains(metadata.id.value));
      expect(indexJson, contains('checksum'));

      final deleted = await backend.delete(metadata.id);
      expect(deleted, isTrue);
      expect(await backend.contains(metadata.id), isFalse);

      final afterDelete = indexFile.readAsStringSync();
      expect(afterDelete, isNot(contains(metadata.id.value)));
    });

    test(
      'contains reports false when the index is stale and the file is missing',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'pqkeystore-stale-index-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final backend = FileKeystoreBackend(tempDir);
        final metadata = KeyMetadata(
          id: const KeyId('stale-index-key'),
          kind: KeyKind.mlKemSecret,
          algorithm: 'ML-KEM-768',
          createdAt: DateTime.utc(2025, 1, 1),
        );
        final record = SealedRecord(
          metadata: metadata,
          wrapAlg: 'pqforge-argon2id-aes-256-gcm-v1',
          ciphertext: Uint8List.fromList(utf8.encode('ciphertext')),
          aad: Uint8List.fromList(utf8.encode('aad')),
          nonce: Uint8List.fromList([1, 2, 3, 4]),
        );

        await backend.putSealed(metadata.id, record);
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}${metadata.id.value}.pqks',
        );
        file.deleteSync();

        expect(await backend.contains(metadata.id), isFalse);
      },
    );
  });
}
