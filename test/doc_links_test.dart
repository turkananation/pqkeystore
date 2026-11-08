// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Local Markdown links must resolve. External URLs are not fetched.
// A missing target fails this test; it is not skipped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local Markdown links resolve', () {
    final root = Directory.current;
    final files = root.listSync(recursive: true).whereType<File>().where((
      file,
    ) {
      final path = file.path;
      return path.endsWith('.md') &&
          !path.contains('${Platform.pathSeparator}.dart_tool') &&
          !path.contains(
            '${Platform.pathSeparator}.git${Platform.pathSeparator}',
          ) &&
          !path.contains(
            '${Platform.pathSeparator}build${Platform.pathSeparator}',
          ) &&
          !path.contains('.plugin_symlinks') &&
          !path.contains(
            '${Platform.pathSeparator}ephemeral${Platform.pathSeparator}',
          );
    }).toList();
    expect(files, isNotEmpty);

    final broken = <String>[];
    for (final file in files) {
      final text = _withoutFencedCode(file.readAsStringSync());
      for (final match in _link.allMatches(text)) {
        final raw = match.group(1)!;
        if (raw.startsWith('http:') ||
            raw.startsWith('https:') ||
            raw.startsWith('mailto:')) {
          continue;
        }
        final hash = raw.indexOf('#');
        final pathPart = hash < 0 ? raw : raw.substring(0, hash);
        final anchor = hash < 0 ? null : raw.substring(hash + 1);
        final targetPath = pathPart.isEmpty
            ? file.path
            : file.parent.uri.resolve(pathPart).toFilePath();
        final asFile = File(targetPath);
        final asDirectory = Directory(targetPath);
        if (!asFile.existsSync() && !asDirectory.existsSync()) {
          broken.add('${file.path} -> $raw');
          continue;
        }
        if (anchor != null &&
            anchor.isNotEmpty &&
            asFile.existsSync() &&
            targetPath.endsWith('.md')) {
          final slugs = _headingSlugs(asFile.readAsStringSync());
          if (!slugs.contains(anchor)) {
            broken.add('${file.path} -> $raw (no heading)');
          }
        }
      }
    }
    expect(broken, isEmpty, reason: broken.join('\n'));
  });
}

final _link = RegExp(r'\[[^\]]*\]\(([^)\s]+)\)');
final _heading = RegExp(r'^#{1,6}\s+(.+)$', multiLine: true);

String _withoutFencedCode(String source) {
  final buffer = StringBuffer();
  var fenced = false;
  for (final line in source.split('\n')) {
    if (line.startsWith('```')) {
      fenced = !fenced;
      buffer.writeln();
      continue;
    }
    buffer.writeln(fenced ? '' : line);
  }
  return buffer.toString();
}

Set<String> _headingSlugs(String markdown) {
  final slugs = <String>{};
  for (final match in _heading.allMatches(_withoutFencedCode(markdown))) {
    slugs.add(_slug(match.group(1)!));
  }
  return slugs;
}

String _slug(String heading) {
  final withoutCode = heading.replaceAllMapped(
    RegExp(r'`([^`]*)`'),
    (match) => match.group(1)!,
  );
  // GitHub: drop punctuation other than spaces and hyphens, then turn each
  // space into a hyphen. Do not collapse the doubled hyphen that an em dash
  // leaves behind.
  final kept = withoutCode.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}\- ]', unicode: true),
    '',
  );
  return kept.trim().replaceAll(' ', '-');
}
