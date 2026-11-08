// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// The publish archive is the git tree. A private key or a .pqks record in
// that tree fails this test. The test prints paths, never file contents.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the tree that would be published has no key material', () async {
    final tracked = _paths(await _git(['ls-files', '-z']));
    final extra = _paths(
      await _git(['ls-files', '-o', '--exclude-standard', '-z']),
    );
    final paths = [...tracked, ...extra];
    expect(paths, isNotEmpty);

    // Split so this source file does not itself contain a key header.
    final markers = [
      ['BEGIN ', 'PRIVATE KEY'].join(),
      ['BEGIN ', 'OPENSSH PRIVATE KEY'].join(),
      ['BEGIN ', 'RSA PRIVATE KEY'].join(),
      ['BEGIN ', 'EC PRIVATE KEY'].join(),
    ];
    final forbidden = <String>[];
    for (final path in paths) {
      final name = path.replaceAll(r'\', '/').toLowerCase();
      if (_badName(name)) {
        forbidden.add(path);
        continue;
      }
      final file = File(path);
      if (!file.existsSync() ||
          file.statSync().type != FileSystemEntityType.file) {
        continue;
      }
      final length = file.lengthSync();
      if (length > 1024 * 1024) {
        forbidden.add('$path (larger than 1 MiB)');
        continue;
      }
      final text = String.fromCharCodes(file.readAsBytesSync());
      for (final marker in markers) {
        if (text.contains(marker)) {
          forbidden.add('$path (private-key block)');
          break;
        }
      }
    }
    expect(forbidden, isEmpty, reason: forbidden.join('\n'));
  });
}

bool _badName(String name) {
  const suffixes = ['.pqks', '.pem', '.p12', '.keystore', '.jks'];
  for (final suffix in suffixes) {
    if (name.endsWith(suffix)) {
      return true;
    }
  }
  return name == '.env' ||
      name.endsWith('/.env') ||
      name.endsWith('/id_rsa') ||
      name.endsWith('/secret.json') ||
      name.contains('id_rsa');
}

List<String> _paths(String raw) {
  return raw.split('\x00').where((path) => path.isNotEmpty).toList();
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args);
  expect(
    result.exitCode,
    0,
    reason: 'git ${args.join(' ')} failed: ${result.stderr}',
  );
  return result.stdout as String;
}
