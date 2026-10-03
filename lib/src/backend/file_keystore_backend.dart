// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// File-based backend — stores each sealed record as a *.pqks file.
//
// Atomic writes via tmp+rename. chmod 0600 on Unix-like systems.
// Filenames are sanitized to allow only alphanumeric, dash, underscore.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';

/// Filesystem-backed sealed record storage.
///
/// Each [SealedRecord] is stored as a `*.pqks` file in [directory]. A sidecar
/// `.pqks-index.json` keeps a sealed, integrity-checked manifest so list/contains
/// can avoid walking the whole directory every time.
final class FileKeystoreBackend implements PqKeystoreBackend {
  /// Creates a [FileKeystoreBackend] rooted at [directory].
  ///
  /// The directory is created recursively if it does not exist.
  FileKeystoreBackend(this.directory) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  }

  static const int _indexVersion = 1;
  static const String _sealField = 'seal';

  /// The directory where `.pqks` files are stored.
  final Directory directory;

  File _indexFile() =>
      File('${directory.path}${Platform.pathSeparator}.pqks-index.json');

  /// Sanitize a string to contain only safe filename characters.
  String _sanitize(String input) {
    final sanitized = input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (sanitized.isEmpty) {
      throw ArgumentError('KeyId sanitizes to empty string');
    }
    return sanitized;
  }

  /// Get the file path for a given [KeyId].
  File _getFile(KeyId id) {
    final safeName = _sanitize(id.value);
    return File('${directory.path}${Platform.pathSeparator}$safeName.pqks');
  }

  /// Small, stable checksum to detect tampered manifest entries.
  String _checksum(Uint8List bytes) {
    var hash = 2166136261; // FNV-1a 32-bit offset basis.
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, Map<String, dynamic>> _canonicalizeEntries(
    Map<String, Map<String, dynamic>> entries,
  ) {
    final sorted = entries.keys.toList()..sort();
    final normalized = <String, Map<String, dynamic>>{};
    for (final key in sorted) {
      final value = entries[key];
      if (value == null) {
        continue;
      }
      normalized[key] = Map<String, dynamic>.from(value);
    }
    return normalized;
  }

  String _indexSeal(Map<String, Map<String, dynamic>> entries) {
    final canonicalEntries = _canonicalizeEntries(entries);
    final payload = jsonEncode({
      'version': _indexVersion,
      'entries': canonicalEntries,
    });
    return _checksum(utf8.encode(payload));
  }

  File _indexEntryFile(String key, Map<String, dynamic> entry) {
    final rawPath = entry['path'];
    if (rawPath is String && rawPath.isNotEmpty) {
      return File(rawPath);
    }
    return _getFile(KeyId(key));
  }

  bool _entryChecksumMatches(Map<String, dynamic> entry, Uint8List bytes) {
    final expected = entry['checksum'];
    if (expected is! String || expected.length != 8) {
      return false;
    }
    return expected == _checksum(bytes);
  }

  Future<Map<String, Map<String, dynamic>>> _readIndex() async {
    final indexFile = _indexFile();
    if (!indexFile.existsSync()) {
      return <String, Map<String, dynamic>>{};
    }

    try {
      final json = jsonDecode(indexFile.readAsStringSync());
      if (json is! Map) {
        return <String, Map<String, dynamic>>{};
      }

      final version = json['version'];
      final entries = json['entries'];
      final seal = json[_sealField];
      if (version != _indexVersion || entries is! Map || seal is! String) {
        return <String, Map<String, dynamic>>{};
      }

      final parsed = <String, Map<String, dynamic>>{};
      for (final entry in entries.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          final normalized = Map<String, dynamic>.from(value);
          if (normalized['path'] is String &&
              normalized['checksum'] is String) {
            parsed[key] = normalized;
          }
        }
      }

      if (_indexSeal(parsed) != seal) {
        return <String, Map<String, dynamic>>{};
      }
      return parsed;
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _writeIndex(Map<String, Map<String, dynamic>> entries) async {
    final indexFile = _indexFile();
    final tmpFile = File('${indexFile.path}.tmp');
    final normalized = _canonicalizeEntries(entries);

    final payload = jsonEncode({
      'version': _indexVersion,
      'entries': normalized,
      _sealField: _indexSeal(normalized),
    });

    tmpFile.writeAsStringSync(payload, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync('chmod', ['600', tmpFile.path]);
    }

    if (indexFile.existsSync()) {
      indexFile.deleteSync();
    }
    tmpFile.renameSync(indexFile.path);
  }

  Future<Map<String, Map<String, dynamic>>> _rebuildIndex() async {
    final entries = <String, Map<String, dynamic>>{};
    if (!directory.existsSync()) {
      return entries;
    }

    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.pqks')) {
        continue;
      }

      try {
        final bytes = entity.readAsBytesSync();
        final record = SealedRecord.decode(Uint8List.fromList(bytes));
        entries[record.metadata.id.value] = {
          'path': entity.path,
          'checksum': _checksum(bytes),
          'kind': record.metadata.kind.name,
          'purpose': record.metadata.purpose,
        };
      } catch (_) {
        // Ignore malformed files while rebuilding the index.
      }
    }

    await _writeIndex(entries);
    return entries;
  }

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) async {
    final file = _getFile(id);
    final tmpFile = File('${file.path}.tmp');
    final encoded = record.encode();

    if (file.existsSync()) {
      file.deleteSync();
    }

    tmpFile.writeAsBytesSync(encoded, flush: true);
    if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync('chmod', ['600', tmpFile.path]);
    }
    tmpFile.renameSync(file.path);

    final index = await _readIndex();
    index[id.value] = {
      'path': file.path,
      'checksum': _checksum(encoded),
      'kind': record.metadata.kind.name,
      'purpose': record.metadata.purpose,
    };
    await _writeIndex(index);
  }

  @override
  Future<SealedRecord?> getSealed(KeyId id) async {
    final file = _getFile(id);
    if (!file.existsSync()) {
      final index = await _readIndex();
      final entry = index[id.value];
      if (entry != null) {
        index.remove(id.value);
        await _writeIndex(index);
      }
      return null;
    }
    final bytes = file.readAsBytesSync();
    final index = await _readIndex();
    final entry = index[id.value];
    if (entry != null && !_entryChecksumMatches(entry, bytes)) {
      index.remove(id.value);
      await _writeIndex(index);
      return null;
    }
    return SealedRecord.decode(Uint8List.fromList(bytes));
  }

  @override
  Future<bool> delete(KeyId id) async {
    final file = _getFile(id);
    final index = await _readIndex();
    final existed = file.existsSync();
    if (!existed && !index.containsKey(id.value)) {
      return false;
    }

    if (existed) {
      file.deleteSync();
    }
    index.remove(id.value);
    await _writeIndex(index);
    return true;
  }

  @override
  Future<bool> contains(KeyId id) async {
    final file = _getFile(id);
    if (file.existsSync()) {
      final index = await _readIndex();
      final entry = index[id.value];
      if (entry != null) {
        final bytes = file.readAsBytesSync();
        if (!_entryChecksumMatches(entry, bytes)) {
          index.remove(id.value);
          await _writeIndex(index);
          return false;
        }
      }
      return true;
    }

    final index = await _readIndex();
    final entry = index[id.value];
    if (entry == null) {
      return false;
    }

    final staleFile = _indexEntryFile(id.value, entry);
    if (!staleFile.existsSync()) {
      index.remove(id.value);
      await _writeIndex(index);
      return false;
    }

    return true;
  }

  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) async {
    while (true) {
      final records = <SealedRecord>[];
      if (!directory.existsSync()) {
        return records;
      }

      var index = await _readIndex();
      if (index.isEmpty) {
        index = await _rebuildIndex();
      }

      var needsRebuild = false;
      for (final entry in index.entries) {
        final path = entry.value['path'] as String?;
        final file = path == null ? _getFile(KeyId(entry.key)) : File(path);
        if (!file.existsSync()) {
          continue;
        }

        try {
          final bytes = file.readAsBytesSync();
          final checksum = entry.value['checksum'] as String?;
          if (checksum != null && checksum != _checksum(bytes)) {
            needsRebuild = true;
            break;
          }

          final record = SealedRecord.decode(Uint8List.fromList(bytes));
          final matchesKind = kind == null || record.metadata.kind == kind;
          final matchesPurpose =
              purpose == null || record.metadata.purpose == purpose;
          if (matchesKind && matchesPurpose) {
            records.add(record);
          }
        } catch (_) {
          needsRebuild = true;
          break;
        }
      }

      if (needsRebuild) {
        await _rebuildIndex();
        continue;
      }

      return records;
    }
  }
}
