// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// PlatformKeystoreBackend tests against the pure-Dart reference of
// platform contract v1. No device or emulator required (AGENTS rule 7).
// StubKeystoreCrypto is NOT SECURE — structure tests only.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

import 'contract/platform_contract_suite.dart';
import 'contract/reference_native_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformContract.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install(Future<Object?> Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  group('contract suite: reference store, no capabilities', () {
    setUpAll(() => install(ReferenceNativeStore().handle));
    tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
    definePlatformContractTests(channel: channel, expectedOs: 'linux');
  });

  group('contract suite: reference store, all capabilities', () {
    setUpAll(
      () => install(
        ReferenceNativeStore(
          os: 'ios',
          supportedOptions: PlatformContract.capabilities,
        ).handle,
      ),
    );
    tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
    definePlatformContractTests(channel: channel, expectedOs: 'ios');
  });

  group('client behavior', () {
    late ReferenceNativeStore store;
    late PlatformKeystoreBackend backend;

    SealedRecord record(String id) => SealedRecord(
      metadata: KeyMetadata(
        id: KeyId(id),
        kind: KeyKind.mlKemSecret,
        algorithm: 'test',
        createdAt: DateTime.utc(2026),
      ),
      wrapAlg: StubKeystoreCrypto.wrapAlgId,
      ciphertext: Uint8List.fromList([1, 2, 3]),
      aad: Uint8List.fromList([4]),
    );

    Future<PlatformError> platformError(Future<Object?> f) async {
      try {
        await f;
      } on PlatformError catch (e) {
        return e;
      }
      fail('expected PlatformError');
    }

    setUp(() {
      store = ReferenceNativeStore();
      install(store.handle);
      backend = PlatformKeystoreBackend(channel: channel);
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('handshake runs once and is cached', () async {
      await backend.contains(const KeyId('a'));
      await backend.contains(const KeyId('b'));
      await backend.listIds();
      expect(store.callCounts[PlatformContract.methodPlatformInfo], 1);
    });

    test('contract version mismatch is refused before any operation', () async {
      store = ReferenceNativeStore(contractVersion: 2);
      install(store.handle);
      final e = await platformError(backend.contains(const KeyId('a')));
      expect(e.code, PlatformErrorCode.contractMismatch);
      expect(store.callCounts[PlatformContract.methodContains], isNull);
    });

    test('failed handshake is retried, not cached', () async {
      var fail = true;
      install((call) async {
        if (fail) {
          throw PlatformException(code: PlatformErrorCode.unavailable);
        }
        return store.handle(call);
      });
      final e = await platformError(backend.platformInfo());
      expect(e.code, PlatformErrorCode.unavailable);
      fail = false;
      expect((await backend.platformInfo()).os, 'linux');
    });

    test('missing plugin maps to UNAVAILABLE', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final e = await platformError(backend.contains(const KeyId('a')));
      expect(e.code, PlatformErrorCode.unavailable);
    });

    test('malformed platformInfo is a contract mismatch', () async {
      for (final bad in <Object?>[
        null,
        'x',
        {
          'contractVersion': 1,
          'os': 'beos',
          'backend': 'x',
          'supportedOptions': <String>[],
        },
        {
          'contractVersion': 1,
          'os': 'linux',
          'backend': '',
          'supportedOptions': <String>[],
        },
        {
          'contractVersion': 1,
          'os': 'linux',
          'backend': 'x',
          'supportedOptions': ['teleport'],
        },
      ]) {
        install((_) async => bad);
        final b = PlatformKeystoreBackend(channel: channel);
        final e = await platformError(b.platformInfo());
        expect(e.code, PlatformErrorCode.contractMismatch, reason: '$bad');
      }
    });

    test(
      'non-boolean delete/contains results are contract violations',
      () async {
        install(
          (call) async => call.method == PlatformContract.methodPlatformInfo
              ? store.handle(call)
              : null,
        );
        expect(
          (await platformError(backend.delete(const KeyId('a')))).code,
          PlatformErrorCode.contractMismatch,
        );
        expect(
          (await platformError(backend.contains(const KeyId('a')))).code,
          PlatformErrorCode.contractMismatch,
        );
      },
    );

    test('native error codes map to typed errors', () {
      PqKeystoreError map(String code) =>
          PlatformKeystoreBackend.mapPlatformException(
            PlatformException(code: code, message: 'm'),
          );
      expect(map(PlatformErrorCode.userCancelled), isA<Cancelled>());
      for (final code in PlatformErrorCode.nativeCodes.difference({
        PlatformErrorCode.userCancelled,
      })) {
        expect((map(code) as PlatformError).code, code);
      }
      expect(
        (map('KEYSTORE_ERROR') as PlatformError).code,
        PlatformErrorCode.storageError,
      );
    });

    test('invalid IDs are rejected in Dart before the channel', () async {
      for (final id in ['', 'a\u0000', '\uD800', 'x\uDC00y', 'a' * 257]) {
        final e = await platformError(backend.contains(KeyId(id)));
        expect(e.code, PlatformErrorCode.invalidArgs);
      }
      expect(store.callCounts[PlatformContract.methodContains], isNull);
      // A correctly paired surrogate is fine.
      expect(await backend.contains(const KeyId('🔑')), isFalse);
    });

    test('putSealed refuses a record whose metadata ID differs', () async {
      final e = await platformError(
        backend.putSealed(const KeyId('a'), record('b')),
      );
      expect(e.code, PlatformErrorCode.invalidArgs);
      expect(store.callCounts[PlatformContract.methodPut], isNull);
    });

    test('getSealed rejects a record stored under a different ID', () async {
      store.tamper('a', record('b').encode());
      expect(
        () => backend.getSealed(const KeyId('a')),
        throwsA(isA<FormatError>()),
      );
    });

    test('getSealed reports undecodable bytes as FormatError', () async {
      store.tamper('a', Uint8List.fromList(utf8.encode('not pqks')));
      expect(
        () => backend.getSealed(const KeyId('a')),
        throwsA(isA<FormatError>()),
      );
    });

    test('list propagates corrupt entries instead of hiding them', () async {
      await backend.putSealed(const KeyId('good'), record('good'));
      store.tamper('bad', Uint8List.fromList([0, 1, 2]));
      expect(backend.list, throwsA(isA<FormatError>()));
      expect(await backend.listIds(), ['bad', 'good']);
      expect(await backend.delete(const KeyId('bad')), isTrue);
      expect(await backend.list(), hasLength(1));
    });

    test('synchronizable + access control is rejected client-side', () async {
      store = ReferenceNativeStore(
        supportedOptions: PlatformContract.capabilities,
      );
      install(store.handle);
      final b = PlatformKeystoreBackend(
        channel: channel,
        options: const PlatformStoreOptions(
          synchronizable: true,
          requireBiometric: true,
        ),
      );
      final e = await platformError(b.putSealed(const KeyId('a'), record('a')));
      expect(e.code, PlatformErrorCode.unsupportedOption);
      expect(store.callCounts[PlatformContract.methodPut], isNull);
    });

    test('options serialize with exactly the four v1 keys', () {
      const options = PlatformStoreOptions(
        accessibility: PlatformAccessibility.afterFirstUnlock,
      );
      expect(options.toChannelMap().keys.toSet(), PlatformContract.optionKeys);
      expect(options.requiredCapabilities, {
        PlatformContract.capAccessibilityAfterFirstUnlock,
      });
      expect(const PlatformStoreOptions().requiredCapabilities, isEmpty);
    });
  });
}
