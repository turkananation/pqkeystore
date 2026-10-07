// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// FallbackKeystoreBackend tests: secure store = contract reference behind a
// switchable "unavailable" fault; fallback = real FileKeystoreBackend.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

import 'contract/reference_native_store.dart';

SealedRecord record(String id, {List<int> body = const [1]}) => SealedRecord(
      metadata: KeyMetadata(
        id: KeyId(id),
        kind: KeyKind.mlKemSecret,
        algorithm: 'test',
        createdAt: DateTime.utc(2026),
        purpose: 'p',
      ),
      wrapAlg: StubKeystoreCrypto.wrapAlgId,
      ciphertext: Uint8List.fromList(body),
      aad: Uint8List.fromList([4]),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PlatformContract.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late ReferenceNativeStore native;
  late FallbackKeystoreBackend backend;
  late FileKeystoreBackend files;
  late List<PlatformError> fallbacks;
  String? fault; // Error code injected for every storage call, if set.

  FallbackKeystoreBackend build({PlatformStoreOptions? options}) =>
      FallbackKeystoreBackend(
        secure: PlatformKeystoreBackend(
          channel: channel,
          options: options ?? const PlatformStoreOptions(),
        ),
        fallback: files,
        onFallback: fallbacks.add,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pqks-fallback-');
    native = ReferenceNativeStore(
      supportedOptions: {PlatformContract.capAccessibilityWhenUnlocked},
    );
    fault = null;
    fallbacks = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fault != null && call.method != PlatformContract.methodPlatformInfo) {
        throw PlatformException(code: fault!, message: 'injected');
      }
      return native.handle(call);
    });
    files = FileKeystoreBackend(dir);
    backend = build();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  Future<Uint8List?> nativeBytes(String id) async =>
      await native.handle(MethodCall(PlatformContract.methodGet, {'id': id}))
          as Uint8List?;

  test('secure available: writes go to secure storage only', () async {
    await backend.putSealed(const KeyId('a'), record('a'));
    expect(await nativeBytes('a'), isNotNull);
    expect(await files.contains(const KeyId('a')), isFalse);
    expect(await backend.locate(const KeyId('a')), StorageLocation.secure);
    expect(fallbacks, isEmpty);
  });

  test('UNAVAILABLE: writes go to the fallback and are reported once',
      () async {
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('a'), record('a'));
    await backend.putSealed(const KeyId('b'), record('b'));
    expect(await files.contains(const KeyId('a')), isTrue);
    expect(await backend.locate(const KeyId('a')), StorageLocation.fallback);
    expect(fallbacks, hasLength(1));
    expect(fallbacks.single.code, PlatformErrorCode.unavailable);
  });

  test('other errors are surfaced, never bypassed', () async {
    for (final code in [
      PlatformErrorCode.locked,
      PlatformErrorCode.authFailed,
      PlatformErrorCode.corrupt,
      PlatformErrorCode.storageError,
    ]) {
      fault = code;
      await expectLater(
        backend.putSealed(const KeyId('a'), record('a')),
        throwsA(isA<PlatformError>().having((e) => e.code, 'code', code)),
      );
    }
    fault = PlatformErrorCode.userCancelled;
    await expectLater(
      backend.getSealed(const KeyId('a')),
      throwsA(isA<Cancelled>()),
    );
    expect(await files.contains(const KeyId('a')), isFalse);
  });

  test('options the file store cannot enforce are rejected, not dropped',
      () async {
    final strict = build(
      options: const PlatformStoreOptions(
        accessibility: PlatformAccessibility.whenUnlocked,
      ),
    );
    fault = PlatformErrorCode.unavailable;
    await expectLater(
      strict.putSealed(const KeyId('a'), record('a')),
      throwsA(
        isA<PlatformError>().having(
          (e) => e.code,
          'code',
          PlatformErrorCode.unsupportedOption,
        ),
      ),
    );
    expect(await files.contains(const KeyId('a')), isFalse);
  });

  test('records written during an outage stay visible after recovery',
      () async {
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('a'), record('a', body: [7]));
    fault = null;
    expect((await backend.getSealed(const KeyId('a')))!.ciphertext, [7]);
    expect((await backend.list()).map((r) => r.metadata.id.value), ['a']);
  });

  test('I1: a newer outage copy wins over the stale secure copy', () async {
    await backend.putSealed(const KeyId('a'), record('a', body: [1]));
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('a'), record('a', body: [2]));
    fault = null;
    expect((await backend.getSealed(const KeyId('a')))!.ciphertext, [2]);
    final listed = await backend.list();
    expect(listed.single.ciphertext, [2]);
  });

  test('migrate on write: a secure write removes the fallback copy', () async {
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('a'), record('a', body: [1]));
    fault = null;
    await backend.putSealed(const KeyId('a'), record('a', body: [3]));
    expect(await files.contains(const KeyId('a')), isFalse);
    expect(await backend.locate(const KeyId('a')), StorageLocation.secure);
    expect((await backend.getSealed(const KeyId('a')))!.ciphertext, [3]);
  });

  test('I2: deleting during an outage cannot resurrect the secure copy',
      () async {
    await backend.putSealed(const KeyId('a'), record('a'));
    fault = PlatformErrorCode.unavailable;
    expect(await backend.delete(const KeyId('a')), isTrue);
    fault = null;
    expect(await backend.getSealed(const KeyId('a')), isNull);
    expect(await backend.contains(const KeyId('a')), isFalse);
    expect(await backend.list(), isEmpty);
    // list() applied the tombstone to secure storage.
    expect(await nativeBytes('a'), isNull);
    // Writing again clears the deletion.
    await backend.putSealed(const KeyId('a'), record('a', body: [5]));
    expect((await backend.getSealed(const KeyId('a')))!.ciphertext, [5]);
  });

  test('list merges both stores and applies filters', () async {
    await backend.putSealed(const KeyId('s'), record('s'));
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('f'), record('f'));
    expect((await backend.list()).map((r) => r.metadata.id.value), ['f']);
    fault = null;
    expect(
      (await backend.list(purpose: 'p')).map((r) => r.metadata.id.value),
      ['f', 's'],
    );
    expect(await backend.list(purpose: 'other'), isEmpty);
  });

  test('migrateToSecure moves sealed records as-is', () async {
    fault = PlatformErrorCode.unavailable;
    await backend.putSealed(const KeyId('a'), record('a', body: [1]));
    await backend.putSealed(const KeyId('b'), record('b', body: [2]));
    expect(await backend.migrateToSecure(), 0);
    fault = null;
    expect(await backend.migrateToSecure(), 2);
    expect(await files.list(), isEmpty);
    expect(await nativeBytes('a'), record('a', body: [1]).encode());
  });

  test('works through the PqKeystore facade during an outage', () async {
    fault = PlatformErrorCode.unavailable;
    final keystore = PqKeystore(backend: backend, crypto: StubKeystoreCrypto());
    final unlock = PassphraseUnlock(Uint8List.fromList([1, 2, 3]));
    final put = await keystore.put(
      record('k').metadata,
      Uint8List.fromList([9, 9]),
      unlock,
    );
    expect(put, isA<KsSuccess<void>>());
    final used = await keystore.use<List<int>>(
      const KeyId('k'),
      unlock,
      (pt) async => pt.toList(),
    );
    expect(used.when(success: (v) => v, failure: (e) => e), [9, 9]);
  });
}
