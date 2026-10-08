// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// FileKeystoreBackend (file store layout v1) tests. Test data only.
// StubKeystoreCrypto is NOT SECURE — structure tests only.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';

SealedRecord record(String id, {List<int> body = const [1, 2, 3]}) =>
    SealedRecord(
      metadata: KeyMetadata(
        id: KeyId(id),
        kind: KeyKind.mlKemSecret,
        algorithm: 'test',
        createdAt: DateTime.utc(2026),
      ),
      wrapAlg: StubKeystoreCrypto.wrapAlgId,
      ciphertext: Uint8List.fromList(body),
      aad: Uint8List.fromList([4]),
    );

void main() {
  late Directory root;
  late Directory dir;
  late FileKeystoreBackend backend;

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  setUp(() {
    root = Directory.systemTemp.createTempSync('pqks-file-');
    dir = Directory('${root.path}${Platform.pathSeparator}store');
    backend = FileKeystoreBackend(dir);
  });

  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+rwx', root.path]);
    }
    root.deleteSync(recursive: true);
  });

  test('round trip, replace, contains, delete', () async {
    const id = KeyId('k');
    expect(await backend.getSealed(id), isNull);
    expect(await backend.delete(id), isFalse);
    await backend.putSealed(id, record('k'));
    await backend.putSealed(id, record('k', body: [9]));
    expect((await backend.getSealed(id))!.ciphertext, [9]);
    expect(await backend.contains(id), isTrue);
    expect(await backend.delete(id), isTrue);
    expect(await backend.contains(id), isFalse);
  });

  test('files are named by SHA-256 and contain the PQKS record exactly',
      () async {
    await backend.putSealed(const KeyId('k'), record('k'));
    final name = FileKeystoreBackend.fileNameFor(const KeyId('k'));
    expect(name, matches(RegExp(r'^[0-9a-f]{64}\.pqks$')));
    final bytes = File(path(name)).readAsBytesSync();
    expect(ascii.decode(bytes.sublist(0, 4)), 'PQKS');
    expect(bytes, record('k').encode());
  });

  test('BUG-006: IDs that sanitized to the same name no longer alias',
      () async {
    const ids = ['a/b', 'ab', 'a.b', 'Key', 'key', '../ab', 'caf\u00e9',
        'cafe\u0301'];
    for (var i = 0; i < ids.length; i++) {
      await backend.putSealed(KeyId(ids[i]), record(ids[i], body: [i]));
    }
    for (var i = 0; i < ids.length; i++) {
      expect((await backend.getSealed(KeyId(ids[i])))!.ciphertext, [i]);
    }
    final listed = (await backend.list()).map((r) => r.metadata.id.value);
    expect(listed.toSet(), ids.toSet());
  });

  test('BUG-007: a failed replacement keeps the previous record', () async {
    await backend.putSealed(const KeyId('k'), record('k', body: [1]));
    if (Platform.isWindows) {
      return; // Read-only directories are not enforced the same way.
    }
    Process.runSync('chmod', ['500', dir.path]);
    await expectLater(
      backend.putSealed(const KeyId('k'), record('k', body: [2])),
      throwsA(isA<PlatformError>()),
    );
    Process.runSync('chmod', ['700', dir.path]);
    expect((await backend.getSealed(const KeyId('k')))!.ciphertext, [1]);
  });

  test('BUG-009: no index is trusted; outside files are never read', () async {
    final outside = File('${root.path}${Platform.pathSeparator}outside.pqks')
      ..writeAsBytesSync(record('secret-elsewhere').encode());
    await backend.putSealed(const KeyId('k'), record('k'));
    File(path('.pqks-index.json')).writeAsStringSync(jsonEncode({
      'version': 1,
      'entries': {
        'secret-elsewhere': {'path': outside.path, 'checksum': '00000000'},
      },
      'seal': '00000000',
    }));
    final ids = (await backend.list()).map((r) => r.metadata.id.value);
    expect(ids, ['k']);
    expect(await backend.contains(const KeyId('secret-elsewhere')), isFalse);
  });

  test('a record moved under another ID is not an entry', () async {
    await backend.putSealed(const KeyId('a'), record('a'));
    File(path(FileKeystoreBackend.fileNameFor(const KeyId('a'))))
        .copySync(path(FileKeystoreBackend.fileNameFor(const KeyId('b'))));
    expect(await backend.getSealed(const KeyId('b')), isNull);
    expect(await backend.contains(const KeyId('b')), isFalse);
    expect((await backend.list()).map((r) => r.metadata.id.value), ['a']);
    expect(await backend.delete(const KeyId('b')), isFalse);
  });

  test('garbage under an entry name is ignored, then replaceable', () async {
    await backend.putSealed(const KeyId('seed'), record('seed'));
    final name = FileKeystoreBackend.fileNameFor(const KeyId('g'));
    File(path(name)).writeAsBytesSync([0, 1, 2]);
    expect(await backend.getSealed(const KeyId('g')), isNull);
    expect(await backend.list(), hasLength(1));
    await backend.putSealed(const KeyId('g'), record('g'));
    expect(await backend.contains(const KeyId('g')), isTrue);
  });

  test('refuses records whose metadata ID differs, and invalid IDs', () async {
    await expectLater(
      backend.putSealed(const KeyId('a'), record('b')),
      throwsA(isA<PlatformError>()),
    );
    await expectLater(
      backend.getSealed(const KeyId('')),
      throwsA(isA<PlatformError>()),
    );
  });

  test('adopts the legacy sanitized-name layout', () async {
    final legacyDir = Directory('${root.path}${Platform.pathSeparator}legacy')
      ..createSync();
    File('${legacyDir.path}${Platform.pathSeparator}legacykey.pqks')
        .writeAsBytesSync(record('legacy-key').encode());
    File('${legacyDir.path}${Platform.pathSeparator}.pqks-index.json')
        .writeAsStringSync('{}');
    final legacy = FileKeystoreBackend(legacyDir);
    await legacy.putSealed(const KeyId('new'), record('new'));
    expect(await legacy.contains(const KeyId('legacy-key')), isTrue);
    final names = legacyDir.listSync().map((e) => e.uri.pathSegments.last);
    expect(names, isNot(contains('legacykey.pqks')));
    expect(names, isNot(contains('.pqks-index.json')));
    expect(names, contains(FileKeystoreBackend.layoutMarkerName));
  });

  test('refuses an unknown layout marker', () async {
    dir.createSync(recursive: true);
    File(path(FileKeystoreBackend.layoutMarkerName))
        .writeAsStringSync('something-else\n');
    await expectLater(
      FileKeystoreBackend(dir).putSealed(const KeyId('k'), record('k')),
      throwsA(isA<FormatError>()),
    );
  });

  test('removes stale temp files', () async {
    dir.createSync(recursive: true);
    final stale = File(path('x.pqks.tmp-1-1-1'))..writeAsBytesSync([1]);
    stale.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    await backend.putSealed(const KeyId('k'), record('k'));
    expect(stale.existsSync(), isFalse);
  });

  test('POSIX: directory 0700 and files 0600', () async {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    await backend.putSealed(const KeyId('k'), record('k'));
    expect(dir.statSync().mode & 0x1FF, 0x1C0); // 0o700
    final file = File(path(FileKeystoreBackend.fileNameFor(const KeyId('k'))));
    expect(file.statSync().mode & 0x1FF, 0x180); // 0o600
  });

  test('concurrent writes stay consistent', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++)
        backend.putSealed(KeyId('p$i'), record('p$i', body: [i])),
      for (var i = 0; i < 10; i++)
        backend.putSealed(const KeyId('same'), record('same', body: [i])),
    ]);
    expect(await backend.list(), hasLength(21));
    expect((await backend.getSealed(const KeyId('same')))!.ciphertext,
        hasLength(1));
  });

  test('pqforge crypto round trip through the file store', () async {
    final keystore = PqKeystore(backend: backend, crypto: PqForgeKeystoreCrypto());
    final unlock = PassphraseUnlock(Uint8List.fromList(utf8.encode('test-only')));
    final material = Uint8List.fromList(List.generate(32, (i) => i));
    await keystore.put(
      KeyMetadata(
        id: const KeyId('forge'),
        kind: KeyKind.mlKemSecret,
        algorithm: 'test',
        createdAt: DateTime.utc(2026),
      ),
      material,
      unlock,
    );
    final used = await keystore.use<List<int>>(
      const KeyId('forge'),
      unlock,
      (pt) async => pt.toList(),
    );
    expect(used.when(success: (v) => v, failure: (e) => e), material);
  });
}
