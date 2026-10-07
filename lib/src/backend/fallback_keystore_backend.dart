// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Opt-in file fallback for when the OS secure-storage facility is absent
// (ADR-0010). On-disk artifacts: doc/FORMATS.md §7–§8.
//
// Trigger: ONLY PlatformError(code: UNAVAILABLE) from the secure backend.
// LOCKED, USER_CANCELLED, AUTH_FAILED, CORRUPT, ... are surfaced, never
// bypassed. Writes that request storage options the file store cannot
// enforce are rejected with UNSUPPORTED_OPTION, never downgraded.
//
// Consistency invariants:
//   I1  A successful secure write leaves no fallback copy of that ID (or, if
//       removal fails, an identical one). Therefore an existing fallback copy
//       is never older than the secure copy, and reads prefer it.
//   I2  A delete while the secure store is unavailable leaves a tombstone, so
//       the secure copy cannot resurface; tombstones are applied to the
//       secure store as soon as it is reachable again.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../api/errors.dart';
import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';
import 'file_keystore_backend.dart';
import 'platform_contract.dart';
import 'platform_keystore_backend.dart';

/// Where a record currently lives.
enum StorageLocation {
  /// The OS secure-storage facility (keychain, keystore, Secret Service, ...).
  secure,

  /// The opt-in fallback directory.
  fallback,
}

/// Secure platform storage with an explicit, opt-in file fallback.
///
/// ```dart
/// final backend = FallbackKeystoreBackend(
///   secure: PlatformKeystoreBackend(),
///   fallback: FileKeystoreBackend(Directory(appSupportDir)),
///   onFallback: (reason) => showWarning('Using file storage: $reason'),
/// );
/// ```
final class FallbackKeystoreBackend implements PqKeystoreBackend {
  /// Creates a fallback-capable backend.
  FallbackKeystoreBackend({
    required this.secure,
    required this.fallback,
    this.onFallback,
  });

  /// Preferred storage.
  final PlatformKeystoreBackend secure;

  /// Used only while [secure] reports `UNAVAILABLE`.
  final FileKeystoreBackend fallback;

  /// Invoked when an operation is served by the fallback because the secure
  /// store is unavailable (once per availability transition).
  final void Function(PlatformError reason)? onFallback;

  bool _inFallback = false;

  static const String _tombstoneDirName = '.tombstones';

  Directory get _tombstoneDir => Directory(
        '${fallback.directory.path}${Platform.pathSeparator}$_tombstoneDirName',
      );

  File _tombstoneFor(KeyId id) => File(
        '${_tombstoneDir.path}${Platform.pathSeparator}'
        '${sha256.convert(utf8.encode(id.value))}.deleted',
      );

  /// Runs [op] on the secure store. Returns `(value, true)` on success and
  /// `(null, false)` if the secure store is unavailable. Other errors throw.
  Future<(T?, bool)> _trySecure<T>(Future<T> Function() op) async {
    try {
      final value = await op();
      if (_inFallback) {
        _inFallback = false;
      }
      return (value, true);
    } on PlatformError catch (e) {
      if (e.code != PlatformErrorCode.unavailable) {
        rethrow;
      }
      if (!_inFallback) {
        _inFallback = true;
        onFallback?.call(e);
      }
      return (null, false);
    }
  }

  /// Applies pending tombstones once the secure store is reachable (I2).
  Future<void> _applyTombstones() async {
    if (!_tombstoneDir.existsSync()) {
      return;
    }
    await for (final entity in _tombstoneDir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final id = await _readTombstone(entity);
      if (id == null) {
        await entity.delete();
        continue;
      }
      final (_, ok) = await _trySecure(() => secure.delete(id));
      if (!ok) {
        return; // Still unavailable; keep the remaining tombstones.
      }
      await entity.delete();
    }
  }

  static void _restrictPosix(String path, String mode) {
    if (!(Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    try {
      Process.runSync('chmod', [mode, path]);
    } on ProcessException {
      // Best effort; the directory is private on mobile/Windows already.
    }
  }

  Future<KeyId?> _readTombstone(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map && json['v'] == 1 && json['id'] is String) {
        final id = KeyId(json['id'] as String);
        validatePlatformKeyId(id);
        if (file.uri.pathSegments.last ==
            '${sha256.convert(utf8.encode(id.value))}.deleted') {
          return id;
        }
      }
    } catch (_) {
      // Malformed tombstone: treated as absent.
    }
    return null;
  }

  Future<bool> _isTombstoned(KeyId id) async =>
      await _readTombstone(_tombstoneFor(id)) != null;

  Future<void> _writeTombstone(KeyId id) async {
    await _tombstoneDir.create(recursive: true);
    final file = _tombstoneFor(id);
    // Create empty and restrict before content hits the disk.
    await file.create(exclusive: true);
    _restrictPosix(_tombstoneDir.path, '700');
    _restrictPosix(file.path, '600');
    await file.writeAsString(jsonEncode({'v': 1, 'id': id.value}), flush: true);
  }

  Future<void> _clearTombstone(KeyId id) async {
    try {
      await _tombstoneFor(id).delete();
    } on PathNotFoundException {
      // Not tombstoned.
    }
  }

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) async {
    final (_, ok) = await _trySecure(() => secure.putSealed(id, record));
    if (ok) {
      await _clearTombstone(id);
      // I1: remove the fallback copy, or make it identical if removal fails.
      try {
        await fallback.delete(id);
      } on PqKeystoreError {
        try {
          await fallback.putSealed(id, record);
        } on PqKeystoreError {
          throw const PlatformError(
            'stored securely, but a stale fallback copy could not be removed',
            code: PlatformErrorCode.storageError,
          );
        }
      }
      return;
    }
    final required = secure.options.requiredCapabilities;
    if (required.isNotEmpty) {
      throw PlatformError(
        'secure storage unavailable and the file fallback cannot enforce: '
        '${(required.toList()..sort()).join(', ')}',
        code: PlatformErrorCode.unsupportedOption,
      );
    }
    await fallback.putSealed(id, record);
    await _clearTombstone(id);
  }

  @override
  Future<SealedRecord?> getSealed(KeyId id) async {
    final local = await fallback.getSealed(id);
    if (local != null) {
      return local; // I1: never older than the secure copy.
    }
    if (await _isTombstoned(id)) {
      return null; // I2.
    }
    final (record, _) = await _trySecure(() => secure.getSealed(id));
    return record;
  }

  @override
  Future<bool> contains(KeyId id) async =>
      await locate(id) != null;

  /// Where [id] currently lives, or `null` if it does not exist.
  Future<StorageLocation?> locate(KeyId id) async {
    if (await fallback.contains(id)) {
      return StorageLocation.fallback;
    }
    if (await _isTombstoned(id)) {
      return null;
    }
    final (found, _) = await _trySecure(() => secure.contains(id));
    return found == true ? StorageLocation.secure : null;
  }

  @override
  Future<bool> delete(KeyId id) async {
    final fromFallback = await fallback.delete(id);
    final (fromSecure, ok) = await _trySecure(() => secure.delete(id));
    if (ok) {
      await _clearTombstone(id);
      return fromFallback || fromSecure == true;
    }
    // Secure store unreachable: it may still hold a copy (I2). The ID is now
    // guaranteed absent, so the delete is reported as effective.
    await _writeTombstone(id);
    return true;
  }

  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) async {
    // Apply pending deletions first so a tombstoned record is never read
    // back from secure storage (I2). Remaining tombstones still filter below.
    await _applyTombstones();
    final (secureRecords, _) = await _trySecure(
      () => secure.list(kind: kind, purpose: purpose),
    );
    final byId = <String, SealedRecord>{};
    for (final record in secureRecords ?? const <SealedRecord>[]) {
      if (!await _isTombstoned(record.metadata.id)) {
        byId[record.metadata.id.value] = record;
      }
    }
    for (final record in await fallback.list(kind: kind, purpose: purpose)) {
      byId[record.metadata.id.value] = record; // I1: fallback wins.
    }
    final ids = byId.keys.toList()..sort();
    return [for (final id in ids) byId[id]!];
  }

  /// Moves every fallback record into secure storage. Sealed records are
  /// moved as-is; no plaintext is involved. Returns the number migrated.
  /// Stops early (without error) if the secure store becomes unavailable.
  Future<int> migrateToSecure() async {
    var moved = 0;
    await _applyTombstones();
    for (final record in await fallback.list()) {
      final id = record.metadata.id;
      final (_, ok) = await _trySecure(() => secure.putSealed(id, record));
      if (!ok) {
        break;
      }
      await fallback.delete(id);
      moved++;
    }
    return moved;
  }
}
