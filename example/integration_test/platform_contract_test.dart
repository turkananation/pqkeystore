// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Runs platform channel contract v1 against the REAL native implementation
// of the current OS. ADR-0001: a platform counts as supported only when this
// passes in CI on that platform.
//
//   flutter test integration_test/platform_contract_test.dart -d <device>
//
// Uses test-only data under the `pqks-contract-test/` ID namespace and
// removes it afterwards. StubKeystoreCrypto (NOT SECURE) is used only to
// exercise facade wiring.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

// The suite is shared with the package's pure-Dart unit tests.
// ignore: avoid_relative_lib_imports
import '../../test/contract/platform_contract_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  definePlatformContractTests(
    channel: const MethodChannel(PlatformContract.channelName),
    expectedOs: Platform.operatingSystem,
  );

  test('pqforge crypto round-trips through the native backend', () async {
    const id = KeyId('pqks-contract-test/pqforge');
    final keystore = PqKeystore(
      backend: PlatformKeystoreBackend(),
      crypto: PqForgeKeystoreCrypto(),
    );
    final unlock = PassphraseUnlock(
      Uint8List.fromList(utf8.encode('integration-test-only')),
    );
    final material = Uint8List.fromList(List.generate(48, (i) => i * 5));
    try {
      final put = await keystore.put(
        KeyMetadata(
          id: id,
          kind: KeyKind.mlKemSecret,
          algorithm: 'test',
          createdAt: DateTime.utc(2026),
        ),
        material,
        unlock,
      );
      expect(put, isA<KsSuccess<void>>());
      final used = await keystore.use<List<int>>(
        id,
        unlock,
        (pt) async => pt.toList(),
      );
      expect(used.when(success: (v) => v, failure: (e) => e), material);
    } finally {
      await keystore.delete(id);
    }
  });
}
