// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Linux only: proves there is NO silent file fallback. Run in a session with
// no Secret Service provider (CI does this with an empty D-Bus session):
//
//   dbus-run-session -- flutter test \
//     integration_test/linux_no_secret_service_test.dart -d linux \
//     --dart-define=PQKS_EXPECT_NO_SECRET_SERVICE=true

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

const bool _enabled = bool.fromEnvironment('PQKS_EXPECT_NO_SECRET_SERVICE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every storage operation fails with UNAVAILABLE',
    () async {
      final backend = PlatformKeystoreBackend();
      // The handshake itself is local and must still succeed.
      expect((await backend.platformInfo()).os, 'linux');

      const id = KeyId('pqks-contract-test/unavailable');
      final record = SealedRecord(
        metadata: KeyMetadata(
          id: id,
          kind: KeyKind.mlKemSecret,
          algorithm: 'test',
          createdAt: DateTime.utc(2026),
        ),
        wrapAlg: StubKeystoreCrypto.wrapAlgId,
        ciphertext: Uint8List.fromList([1]),
        aad: Uint8List.fromList([2]),
      );
      final operations = <String, Future<Object?> Function()>{
        'put': () => backend.putSealed(id, record),
        'get': () => backend.getSealed(id),
        'contains': () => backend.contains(id),
        'delete': () => backend.delete(id),
        'listIds': backend.listIds,
      };
      for (final entry in operations.entries) {
        await expectLater(
          entry.value(),
          throwsA(
            isA<PlatformError>().having(
              (e) => e.code,
              'code',
              PlatformErrorCode.unavailable,
            ),
          ),
          reason: entry.key,
        );
      }
    },
    skip: !Platform.isLinux || !_enabled
        ? 'Linux only; set PQKS_EXPECT_NO_SECRET_SERVICE=true'
        : false,
  );
}
