// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// File-based backend — one PQKS record per file. Layout spec: doc/FORMATS.md
// §7 ("file store v1"). Threat model: ADR-0003, ADR-0010.
//
// Design rules:
//   • File name = lowercase hex SHA-256 of the UTF-8 ID + ".pqks". Injective in
//     practice, safe on case-insensitive filesystems, never a path.
//   • File content = the PQKS record exactly (SealedRecord.encode()). The ID is
//     read back from the record's metadata and must match the requested ID.
//   • No index: nothing persisted can point outside the directory.
//   • Replace = unique temp file in the same directory, flush, rename over the
//     old file. The previous record survives any failure before the rename.
//   • POSIX desktop: directories created here are 0700, files 0600, verified.
//
// The protection of a stored key is the PQKS inner wrapping done by the
// configured PqKeystoreCrypto (e.g. pqforge passphrase wrapping). Metadata is
// cleartext. Use a dedicated directory.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../api/errors.dart';
import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';
import 'platform_contract.dart';

/// Filesystem-backed sealed record storage (file store layout v1).
final class FileKeystoreBackend implements PqKeystoreBackend {
  /// Creates a [FileKeystoreBackend] rooted at [directory].
  ///
  /// The directory is created if missing (0700 on Linux/macOS). An existing
  /// directory's permissions are not changed; point this at a dedicated
  /// directory, not a shared one such as Documents.
  FileKeystoreBackend(this.directory) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
      _restrict(directory.path, '700');
    }
  }

  /// Layout version marker written into the directory.
  static const String layoutMarkerName = '.pqkeystore-layout';
  static const String _layoutMarker = 'pqkeystore-file-store-v1\n';
  static const String _extension = '.pqks';
  static const String _tempMarker = '.tmp';
  static final RegExp _entryName = RegExp(r'^[0-9a-f]{64}\.pqks$');

  /// Headroom over the record limit when reading untrusted files.
  static const int _maxFileBytes = PlatformContract.maxRecordBytes + 64 * 1024;

  /// The directory where `.pqks` files are stored.
  final Directory directory;

  final Random _random = Random.secure();
  int _tempCounter = 0;
  Future<void> _tail = Future<void>.value();
  bool _prepared = false;

  /// File name for [id] (no directory).
  static String fileNameFor(KeyId id) =>
      '${sha256.convert(utf8.encode(id.value))}$_extension';

  File _fileFor(KeyId id) =>
      File('${directory.path}${Platform.pathSeparator}${fileNameFor(id)}');

  /// Serializes operations within this instance (in-process linearizability).
  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) => _locked(() async {
    validatePlatformKeyId(id);
    if (record.metadata.id != id) {
      throw const PlatformError(
        'record metadata ID does not match the storage ID',
        code: PlatformErrorCode.invalidArgs,
      );
    }
    final encoded = record.encode();
    if (encoded.length > PlatformContract.maxRecordBytes) {
      throw const PlatformError(
        'encoded record exceeds ${PlatformContract.maxRecordBytes} bytes',
        code: PlatformErrorCode.invalidArgs,
      );
    }
    await _prepare();
    final target = _fileFor(id);
    final temp = File(
      '${target.path}$_tempMarker$pid-${++_tempCounter}-'
      '${_random.nextInt(1 << 32).toRadixString(16)}',
    );
    try {
      // Create empty, restrict, then write: content is never exposed
      // under default permissions.
      await temp.create(exclusive: true);
      _restrict(temp.path, '600');
      await temp.writeAsBytes(encoded, flush: true);
      await temp.rename(target.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw PlatformError(
        'cannot write record (${e.osError?.errorCode ?? 'io'})',
        code: PlatformErrorCode.storageError,
      );
    }
  });

  @override
  Future<SealedRecord?> getSealed(KeyId id) => _locked(() async {
    validatePlatformKeyId(id);
    return _read(_fileFor(id), expected: id);
  });

  @override
  Future<bool> delete(KeyId id) => _locked(() async {
    validatePlatformKeyId(id);
    final file = _fileFor(id);
    final valid = await _read(file, expected: id) != null;
    try {
      await file.delete();
    } on PathNotFoundException {
      return false;
    } on FileSystemException catch (e) {
      throw PlatformError(
        'cannot delete record (${e.osError?.errorCode ?? 'io'})',
        code: PlatformErrorCode.storageError,
      );
    }
    // A file that was not a valid record for this ID is removed but was
    // not an entry.
    return valid;
  });

  @override
  Future<bool> contains(KeyId id) => _locked(() async {
    validatePlatformKeyId(id);
    return await _read(_fileFor(id), expected: id) != null;
  });

  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) =>
      _locked(() async {
        final records = <SealedRecord>[];
        if (!directory.existsSync()) {
          return records;
        }
        await for (final entity in directory.list(followLinks: false)) {
          final name = entity.uri.pathSegments.last;
          if (entity is! File || !_entryName.hasMatch(name)) {
            continue;
          }
          final record = await _read(entity);
          // A file must live under its own ID's name; moved files are not
          // entries.
          if (record == null || fileNameFor(record.metadata.id) != name) {
            continue;
          }
          if (kind != null && record.metadata.kind != kind) {
            continue;
          }
          if (purpose != null && record.metadata.purpose != purpose) {
            continue;
          }
          records.add(record);
        }
        records.sort(
          (a, b) => a.metadata.id.value.compareTo(b.metadata.id.value),
        );
        return records;
      });

  /// Reads a record. Returns null for missing files and for files that are
  /// not a valid PQKS record (for [expected], under that ID).
  Future<SealedRecord?> _read(File file, {KeyId? expected}) async {
    final Uint8List bytes;
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > _maxFileBytes) {
        return null;
      }
      bytes = await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (e) {
      throw PlatformError(
        'cannot read record (${e.osError?.errorCode ?? 'io'})',
        code: PlatformErrorCode.storageError,
      );
    }
    try {
      final record = SealedRecord.decode(bytes);
      if (expected != null && record.metadata.id != expected) {
        return null;
      }
      return record;
    } catch (_) {
      return null;
    }
  }

  /// One-time directory preparation: layout marker, legacy adoption, and
  /// cleanup of temp files left by a crash.
  Future<void> _prepare() async {
    if (_prepared) {
      return;
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      _restrict(directory.path, '700');
    }
    final marker = File(
      '${directory.path}${Platform.pathSeparator}'
      '$layoutMarkerName',
    );
    if (marker.existsSync()) {
      final content = await marker.readAsString();
      if (content != _layoutMarker) {
        throw const FormatError(
          'directory uses an unknown pqkeystore file layout',
        );
      }
    } else {
      await _adoptLegacyLayout();
      await marker.writeAsString(_layoutMarker, flush: true);
    }
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          entity.path.contains(_tempMarker) &&
          entity.statSync().modified.isBefore(cutoff)) {
        await _deleteQuietly(entity);
      }
    }
    _prepared = true;
  }

  /// Migrates the pre-v1 layout (sanitized names + `.pqks-index.json`):
  /// each valid record is rewritten under its hashed name; the index is
  /// discarded (it was never trusted for authenticity).
  Future<void> _adoptLegacyLayout() async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File) {
        continue;
      }
      if (name == '.pqks-index.json') {
        await _deleteQuietly(entity);
        continue;
      }
      if (!name.endsWith(_extension) || _entryName.hasMatch(name)) {
        continue;
      }
      final record = await _read(entity);
      if (record == null) {
        continue;
      }
      final target = _fileFor(record.metadata.id);
      if (!target.existsSync()) {
        await entity.rename(target.path);
        _restrict(target.path, '600');
      }
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort.
    }
  }

  /// Restricts permissions on POSIX desktops and verifies the result.
  /// Mobile app sandboxes are already private; Windows inherits the
  /// directory ACL (see doc/platforms/windows.md).
  static void _restrict(String path, String mode) {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    final ProcessResult result;
    try {
      result = Process.runSync('chmod', [mode, path]);
    } on ProcessException {
      throw const PlatformError(
        'cannot restrict file permissions (chmod unavailable)',
        code: PlatformErrorCode.storageError,
      );
    }
    final groupOrOther = File(path).statSync().mode & 0x3F; // 0o077
    if (result.exitCode != 0 || groupOrOther != 0) {
      throw const PlatformError(
        'cannot restrict file permissions',
        code: PlatformErrorCode.storageError,
      );
    }
  }
}
