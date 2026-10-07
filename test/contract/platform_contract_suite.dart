// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform channel contract v1 — shared behavioral suite.
//
// Runs unchanged against:
//   • ReferenceNativeStore (pure Dart, test/platform_backend_test.dart), and
//   • each real native implementation via
//     example/integration_test/platform_contract_test.dart.
//
// ADR-0001: a platform is "supported" only when this suite passes on it.
//
// Rules: test data only, no secrets; IDs are namespaced under [_prefix] and
// removed after every test so the suite is safe on a developer device.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

const String _prefix = 'pqks-contract-test/';

/// Defines the contract suite.
///
/// [channel] must be bound to the implementation under test. [expectedOs]
/// is the `platformInfo.os` value the implementation must report.
void definePlatformContractTests({
  required MethodChannel channel,
  required String expectedOs,
}) {
  late PlatformInfo info;

  Future<Object?> call(String method, [Object? args]) =>
      channel.invokeMethod<Object?>(method, args);

  Map<String, Object> opts({
    bool presence = false,
    bool biometric = false,
    String accessibility = PlatformContract.accessibilityPlatformDefault,
    bool sync = false,
  }) => {
    PlatformContract.optRequireUserPresence: presence,
    PlatformContract.optRequireBiometric: biometric,
    PlatformContract.optAccessibility: accessibility,
    PlatformContract.optSynchronizable: sync,
  };

  Future<void> put(String id, List<int> data, [Map<String, Object>? options]) =>
      call(PlatformContract.methodPut, {
        PlatformContract.argId: id,
        PlatformContract.argData: Uint8List.fromList(data),
        PlatformContract.argOptions: options ?? opts(),
      });

  Future<Uint8List?> get(String id) async =>
      await call(PlatformContract.methodGet, {PlatformContract.argId: id})
          as Uint8List?;

  Future<void> expectCode(Future<Object?> future, String code) async {
    try {
      await future;
    } on PlatformException catch (e) {
      expect(e.code, code, reason: 'message: ${e.message}');
      return;
    }
    fail('expected PlatformException($code)');
  }

  Future<void> cleanup() async {
    final ids = await call(PlatformContract.methodListIds) as List<Object?>;
    for (final id in ids.cast<String>()) {
      if (id.startsWith(_prefix)) {
        await call(PlatformContract.methodDelete, {PlatformContract.argId: id});
      }
    }
  }

  setUpAll(() async {
    info = PlatformInfo.fromChannel(
      await call(PlatformContract.methodPlatformInfo),
    );
    await cleanup();
  });

  tearDown(cleanup);

  group('platformInfo', () {
    test('reports contract v1, the expected OS, and known capabilities', () {
      expect(info.contractVersion, PlatformContract.version);
      expect(info.os, expectedOs);
      expect(info.backend, isNotEmpty);
      expect(
        PlatformContract.capabilities.containsAll(info.supportedOptions),
        isTrue,
      );
    });
  });

  group('missing entries', () {
    test('get → null, contains → false, delete → false', () async {
      const id = '${_prefix}absent';
      expect(await get(id), isNull);
      expect(
        await call(PlatformContract.methodContains, {
          PlatformContract.argId: id,
        }),
        isFalse,
      );
      expect(
        await call(PlatformContract.methodDelete, {PlatformContract.argId: id}),
        isFalse,
      );
    });
  });

  group('CRUD', () {
    test('round-trips every byte value exactly', () async {
      const id = '${_prefix}bytes';
      final data = List<int>.generate(512, (i) => i % 256);
      await put(id, data);
      expect(await get(id), data);
      expect(
        await call(PlatformContract.methodContains, {
          PlatformContract.argId: id,
        }),
        isTrue,
      );
    });

    test('put replaces an existing entry', () async {
      const id = '${_prefix}replace';
      await put(id, [1, 2, 3]);
      await put(id, [9, 8, 7, 6]);
      expect(await get(id), [9, 8, 7, 6]);
      final ids = await call(PlatformContract.methodListIds) as List<Object?>;
      expect(ids.where((e) => e == id), hasLength(1));
    });

    test('delete existing → true, then the entry is gone', () async {
      const id = '${_prefix}delete';
      await put(id, [1]);
      expect(
        await call(PlatformContract.methodDelete, {PlatformContract.argId: id}),
        isTrue,
      );
      expect(await get(id), isNull);
      expect(
        await call(PlatformContract.methodContains, {
          PlatformContract.argId: id,
        }),
        isFalse,
      );
      expect(
        await call(PlatformContract.methodDelete, {PlatformContract.argId: id}),
        isFalse,
      );
    });

    test('accepts maximum record size', () async {
      const id = '${_prefix}max-size';
      final data = List<int>.generate(
        PlatformContract.maxRecordBytes,
        (i) => (i * 31) & 0xff,
      );
      await put(id, data);
      expect(await get(id), data);
    });
  });

  group('listIds', () {
    test(
      'returns exactly the stored IDs (within the test namespace)',
      () async {
        final ids = ['${_prefix}l1', '${_prefix}l2', '${_prefix}l3'];
        for (final id in ids) {
          await put(id, [1]);
        }
        await call(PlatformContract.methodDelete, {
          PlatformContract.argId: ids[1],
        });
        final listed =
            (await call(PlatformContract.methodListIds) as List<Object?>)
                .cast<String>()
                .where((id) => id.startsWith(_prefix))
                .toSet();
        expect(listed, {ids[0], ids[2]});
      },
    );

    test('rejects arguments', () async {
      await expectCode(
        call(PlatformContract.methodListIds, {'x': 1}),
        PlatformErrorCode.invalidArgs,
      );
    });
  });

  group('ID mapping is injective and opaque', () {
    // Each of these must be a distinct entry on every platform, including
    // case-insensitive filesystems and stores that treat IDs as paths.
    final variants = <String>[
      'Key',
      'key',
      'KEY',
      'caf\u00e9', // NFC
      'cafe\u0301', // NFD — must not alias the NFC form
      '../escape',
      '..',
      '.',
      'a/b',
      r'a\b',
      'C:',
      'con',
      'NUL.txt',
      ' spaced ',
      'trailing.',
      'tab\tnewline\n',
      '__meta__x',
      'x__meta__',
      '🔑',
      'a' * (PlatformContract.maxIdUtf8Bytes - _prefix.length),
    ];

    test('distinct IDs never alias', () async {
      for (var i = 0; i < variants.length; i++) {
        await put('$_prefix${variants[i]}', [i, 0xAA]);
      }
      for (var i = 0; i < variants.length; i++) {
        expect(await get('$_prefix${variants[i]}'), [
          i,
          0xAA,
        ], reason: 'variant #$i');
      }
      final listed =
          (await call(PlatformContract.methodListIds) as List<Object?>)
              .cast<String>()
              .where((id) => id.startsWith(_prefix))
              .toSet();
      expect(listed, variants.map((v) => '$_prefix$v').toSet());
    });

    test('deleting one variant leaves the others intact', () async {
      await put('${_prefix}Key', [1]);
      await put('${_prefix}key', [2]);
      await call(PlatformContract.methodDelete, {
        PlatformContract.argId: '${_prefix}Key',
      });
      expect(await get('${_prefix}Key'), isNull);
      expect(await get('${_prefix}key'), [2]);
    });
  });

  group('argument validation', () {
    test('rejects invalid IDs on every method', () async {
      final bad = <Object?>[
        null,
        42,
        '',
        // The Linux embedder codec truncates strings at U+0000 before the
        // plugin sees them; the Dart client is the enforcement point there
        // (doc/PLATFORM_CONTRACT.md §3, known limitation L1).
        if (expectedOs != 'linux') 'nul\u0000byte',
        'a' * (PlatformContract.maxIdUtf8Bytes + 1),
        'é' * (PlatformContract.maxIdUtf8Bytes ~/ 2 + 1), // 2 bytes each
      ];
      for (final id in bad) {
        await expectCode(
          call(PlatformContract.methodPut, {
            PlatformContract.argId: id,
            PlatformContract.argData: Uint8List.fromList([1]),
            PlatformContract.argOptions: opts(),
          }),
          PlatformErrorCode.invalidArgs,
        );
        for (final method in [
          PlatformContract.methodGet,
          PlatformContract.methodDelete,
          PlatformContract.methodContains,
        ]) {
          await expectCode(
            call(method, {PlatformContract.argId: id}),
            PlatformErrorCode.invalidArgs,
          );
        }
      }
    });

    test('rejects non-map arguments and unexpected keys', () async {
      await expectCode(
        call(PlatformContract.methodGet, 'not-a-map'),
        PlatformErrorCode.invalidArgs,
      );
      await expectCode(
        call(PlatformContract.methodGet, null),
        PlatformErrorCode.invalidArgs,
      );
      await expectCode(
        call(PlatformContract.methodGet, {
          PlatformContract.argId: '${_prefix}x',
          'key': '${_prefix}x',
        }),
        PlatformErrorCode.invalidArgs,
      );
    });

    test('rejects empty, oversized, and mistyped data', () async {
      const id = '${_prefix}data';
      for (final data in <Object?>[
        null,
        'string',
        Uint8List(0),
        Uint8List(PlatformContract.maxRecordBytes + 1),
      ]) {
        await expectCode(
          call(PlatformContract.methodPut, {
            PlatformContract.argId: id,
            PlatformContract.argData: data,
            PlatformContract.argOptions: opts(),
          }),
          PlatformErrorCode.invalidArgs,
        );
      }
      expect(await get(id), isNull);
    });

    test('rejects malformed options', () async {
      const id = '${_prefix}opts';
      final malformed = <Object?>[
        null,
        <String, Object>{},
        {...opts(), 'unknown': true},
        Map.of(opts())..remove(PlatformContract.optSynchronizable),
        {...opts(), PlatformContract.optRequireBiometric: 'yes'},
        {...opts(), PlatformContract.optAccessibility: 'always'},
        {...opts(), PlatformContract.optAccessibility: 1},
      ];
      for (final options in malformed) {
        await expectCode(
          call(PlatformContract.methodPut, {
            PlatformContract.argId: id,
            PlatformContract.argData: Uint8List.fromList([1]),
            PlatformContract.argOptions: options,
          }),
          PlatformErrorCode.invalidArgs,
        );
      }
      expect(await get(id), isNull);
    });

    test('unknown methods are not implemented', () async {
      expect(
        () => call('putJson', {PlatformContract.argId: '${_prefix}x'}),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  group('options are enforced or explicitly rejected', () {
    final cases = <String, Map<String, Object>>{
      PlatformContract.capRequireUserPresence: opts(presence: true),
      PlatformContract.capRequireBiometric: opts(biometric: true),
      PlatformContract.capAccessibilityWhenUnlocked: opts(
        accessibility: PlatformContract.accessibilityWhenUnlocked,
      ),
      PlatformContract.capAccessibilityAfterFirstUnlock: opts(
        accessibility: PlatformContract.accessibilityAfterFirstUnlock,
      ),
      PlatformContract.capSynchronizable: opts(sync: true),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final id = '$_prefix${entry.key}';
        if (info.supportedOptions.contains(entry.key)) {
          await put(id, [1, 2], entry.value);
          // Reading auth-protected entries would prompt; existence and
          // deletion must not.
          expect(
            await call(PlatformContract.methodContains, {
              PlatformContract.argId: id,
            }),
            isTrue,
          );
          expect(
            await call(PlatformContract.methodDelete, {
              PlatformContract.argId: id,
            }),
            isTrue,
          );
        } else {
          await expectCode(
            put(id, [1], entry.value),
            PlatformErrorCode.unsupportedOption,
          );
          expect(
            await call(PlatformContract.methodContains, {
              PlatformContract.argId: id,
            }),
            isFalse,
          );
        }
      });
    }

    test('synchronizable + access control is rejected', () async {
      await expectCode(
        put('${_prefix}combo', [1], opts(sync: true, presence: true)),
        PlatformErrorCode.unsupportedOption,
      );
    });

    test('a rejected put leaves the previous entry intact', () async {
      const id = '${_prefix}keep';
      await put(id, [7, 7]);
      final unsupported = PlatformContract.capabilities.difference(
        info.supportedOptions,
      );
      // Pick a request this device must reject.
      final options = unsupported.contains(PlatformContract.capSynchronizable)
          ? opts(sync: true)
          : opts(sync: true, presence: true);
      await expectCode(
        put(id, [1], options),
        PlatformErrorCode.unsupportedOption,
      );
      await expectCode(
        call(PlatformContract.methodPut, {
          PlatformContract.argId: id,
          PlatformContract.argData: Uint8List(0),
          PlatformContract.argOptions: opts(),
        }),
        PlatformErrorCode.invalidArgs,
      );
      expect(await get(id), [7, 7]);
    });
  });

  group('concurrency', () {
    test('parallel writes to distinct IDs all land', () async {
      await Future.wait([
        for (var i = 0; i < 16; i++) put('${_prefix}par-$i', [i]),
      ]);
      for (var i = 0; i < 16; i++) {
        expect(await get('${_prefix}par-$i'), [i]);
      }
    });

    test(
      'parallel writes to one ID leave exactly one complete value',
      () async {
        const id = '${_prefix}race';
        await Future.wait([
          for (var i = 0; i < 8; i++) put(id, List<int>.filled(64, i)),
        ]);
        final value = await get(id);
        expect(value, isNotNull);
        expect(value!.toSet(), hasLength(1));
        expect(value, hasLength(64));
      },
    );
  });

  group('PlatformKeystoreBackend through PqKeystore', () {
    // StubKeystoreCrypto is NOT SECURE — structure tests only.
    late PqKeystore keystore;
    late PlatformKeystoreBackend backend;
    final unlock = PassphraseUnlock(
      Uint8List.fromList(utf8.encode('contract-test-only')),
    );

    KeyMetadata meta(
      String id, {
      KeyKind kind = KeyKind.mlKemSecret,
      String? purpose,
    }) => KeyMetadata(
      id: KeyId('$_prefix$id'),
      kind: kind,
      algorithm: 'test',
      createdAt: DateTime.utc(2026),
      purpose: purpose,
    );

    setUp(() {
      backend = PlatformKeystoreBackend(channel: channel);
      keystore = PqKeystore(backend: backend, crypto: StubKeystoreCrypto());
    });

    test('put → use → metadata → delete', () async {
      final material = Uint8List.fromList(List.generate(32, (i) => i));
      expect(
        await keystore.put(meta('f1'), material, unlock),
        isA<KsSuccess<void>>(),
      );
      final used = await keystore.use<List<int>>(
        const KeyId('${_prefix}f1'),
        unlock,
        (pt) async => pt.toList(),
      );
      expect(used.when(success: (v) => v, failure: (e) => e), material);
      final md = await keystore.metadata(const KeyId('${_prefix}f1'));
      expect(
        md.when(success: (m) => m.kind, failure: (e) => e),
        KeyKind.mlKemSecret,
      );
      expect(
        await keystore.delete(const KeyId('${_prefix}f1')),
        isA<KsSuccess<void>>(),
      );
      final again = await keystore.delete(const KeyId('${_prefix}f1'));
      expect(
        again.when(success: (_) => null, failure: (e) => e),
        isA<NotFound>(),
      );
    });

    test('list filters by kind and purpose from the PQKS record', () async {
      final material = Uint8List.fromList([1, 2, 3]);
      await keystore.put(meta('a', purpose: 'sign'), material, unlock);
      await keystore.put(
        meta('b', kind: KeyKind.classicalEd25519, purpose: 'sign'),
        material,
        unlock,
      );
      await keystore.put(meta('c', purpose: 'enc'), material, unlock);

      Future<Set<String>> ids({KeyKind? kind, String? purpose}) async {
        final r = await keystore.list(kind: kind, purpose: purpose);
        return r.when(
          success: (l) => l
              .map((m) => m.id.value)
              .where((v) => v.startsWith(_prefix))
              .toSet(),
          failure: (e) => throw e,
        );
      }

      expect(await ids(), {'${_prefix}a', '${_prefix}b', '${_prefix}c'});
      expect(await ids(kind: KeyKind.mlKemSecret), {
        '${_prefix}a',
        '${_prefix}c',
      });
      expect(await ids(purpose: 'sign'), {'${_prefix}a', '${_prefix}b'});
      expect(await ids(kind: KeyKind.mlKemSecret, purpose: 'sign'), {
        '${_prefix}a',
      });
    });

    test('IDs beginning with __meta__ are ordinary IDs', () async {
      final material = Uint8List.fromList([4]);
      await keystore.put(meta('__meta__y'), material, unlock);
      final r = await keystore.list();
      final ids = r.when(
        success: (l) => l.map((m) => m.id.value).toSet(),
        failure: (e) => throw e,
      );
      expect(ids, contains('${_prefix}__meta__y'));
    });

    test('unsupported options fail before reaching storage', () async {
      final unsupported = PlatformContract.capabilities.difference(
        info.supportedOptions,
      );
      if (unsupported.isEmpty) {
        return; // Every option is enforceable on this device.
      }
      final strict = PlatformKeystoreBackend(
        channel: channel,
        options: PlatformStoreOptions(
          requireUserPresence: unsupported.contains(
            PlatformContract.capRequireUserPresence,
          ),
          requireBiometric: unsupported.contains(
            PlatformContract.capRequireBiometric,
          ),
          synchronizable:
              unsupported.contains(PlatformContract.capSynchronizable) &&
              !unsupported.contains(PlatformContract.capRequireUserPresence) &&
              !unsupported.contains(PlatformContract.capRequireBiometric),
          accessibility:
              unsupported.contains(
                PlatformContract.capAccessibilityWhenUnlocked,
              )
              ? PlatformAccessibility.whenUnlocked
              : unsupported.contains(
                  PlatformContract.capAccessibilityAfterFirstUnlock,
                )
              ? PlatformAccessibility.afterFirstUnlock
              : PlatformAccessibility.platformDefault,
        ),
      );
      final store = PqKeystore(backend: strict, crypto: StubKeystoreCrypto());
      final r = await store.put(
        meta('strict'),
        Uint8List.fromList([1]),
        unlock,
      );
      final error = r.when(success: (_) => null, failure: (e) => e);
      expect(error, isA<PlatformError>());
      expect(
        (error! as PlatformError).code,
        PlatformErrorCode.unsupportedOption,
      );
      expect(await backend.contains(const KeyId('${_prefix}strict')), isFalse);
    });
  });
}
