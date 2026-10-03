// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform backend — delegates to OS-level secure storage via MethodChannel.
//
// MethodChannel: com.yardenah.pqkeystore/store
// Methods: put, get, delete, contains, putJson, getJson, platformInfo

import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/errors.dart';
import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';
import 'platform_options.dart';

/// Backend that delegates to OS-level secure storage via [MethodChannel].
///
/// Stores PQKS-encoded sealed blobs through the platform channel.
/// Metadata is stored separately with `__meta__` prefixed keys via `putJson`.
///
/// | Platform | Mechanism |
/// |----------|-----------|
/// | Android  | AES-GCM in Android Keystore; blob in SharedPreferences |
/// | iOS      | Keychain generic password, ThisDeviceOnly |
/// | macOS    | Same as iOS |
/// | Windows  | DPAPI CryptProtectData UI_FORBIDDEN |
/// | Linux    | Secret Service or XDG 0600 file fallback |
final class PlatformKeystoreBackend implements PqKeystoreBackend {

  /// Creates a [PlatformKeystoreBackend] with optional [options].
  PlatformKeystoreBackend({
    this.options = const PlatformStoreOptions(),
  });
  /// Frozen MethodChannel name — must match all five platform implementations.
  static const MethodChannel _channel =
      MethodChannel('com.yardenah.pqkeystore/store');

  /// Platform-specific storage options.
  final PlatformStoreOptions options;

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) async {
    try {
      final encoded = record.encode();
      await _channel.invokeMethod<void>('put', {
        'id': id.value,
        'data': encoded,
        'options': options.toChannelMap(),
      });

      // Store metadata with '__meta__' prefix for list filtering
      final metaJson = jsonEncode({
        'kind': record.metadata.kind.name,
        'purpose': record.metadata.purpose,
        'algorithm': record.metadata.algorithm,
      });
      await _channel.invokeMethod<void>('putJson', {
        'id': '__meta__${id.value}',
        'data': metaJson,
        'options': options.toChannelMap(),
      });
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<SealedRecord?> getSealed(KeyId id) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('get', {
        'id': id.value,
      });
      if (bytes == null) {
        return null;
      }
      return SealedRecord.decode(Uint8List.fromList(bytes));
    } on PlatformException catch (e) {
      // NOT_FOUND is expected and returns null
      if (e.code == 'NOT_FOUND') {
        return null;
      }
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<bool> delete(KeyId id) async {
    try {
      final result = await _channel.invokeMethod<bool>('delete', {
        'id': id.value,
      });
      // Best-effort delete of metadata key
      try {
        await _channel.invokeMethod<bool>('delete', {
          'id': '__meta__${id.value}',
        });
      } catch (_) {
        // Ignore errors deleting metadata
      }
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_FOUND') {
        return false;
      }
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<bool> contains(KeyId id) async {
    try {
      final result = await _channel.invokeMethod<bool>('contains', {
        'id': id.value,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) async {
    // NOTE: Platform listing requires a metadata index. This is a
    // best-effort implementation using __meta__ keys.
    // Full index support is a CONTINUE.md task.
    try {
      // This method may not be available on all platforms yet
      final keysList =
          await _channel.invokeListMethod<String>('listIds') ?? [];
      final records = <SealedRecord>[];

      for (final keyIdStr in keysList) {
        if (keyIdStr.startsWith('__meta__')) {
          continue;
        }

        // Pre-filter via metadata before fetching full record
        if (kind != null || purpose != null) {
          try {
            final metaJsonStr =
                await _channel.invokeMethod<String>('getJson', {
              'id': '__meta__$keyIdStr',
            });
            if (metaJsonStr != null) {
              final meta =
                  jsonDecode(metaJsonStr) as Map<String, dynamic>;
              if (kind != null && meta['kind'] != kind.name) {
                continue;
              }
              if (purpose != null && meta['purpose'] != purpose) {
                continue;
              }
            }
          } catch (_) {
            // If metadata fetch fails, include the record anyway
          }
        }

        final record = await getSealed(KeyId(keyIdStr));
        if (record != null) {
          records.add(record);
        }
      }
      return records;
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  /// Map a [PlatformException] to a [PqKeystoreError].
  static PqKeystoreError _mapPlatformError(PlatformException e) {
    return switch (e.code) {
      'NOT_FOUND' => NotFound(KeyId(e.message ?? 'unknown')),
      'USER_CANCELLED' => const Cancelled(),
      'AUTH_FAILED' => PlatformError(e.message ?? 'Authentication failed',
          code: 'AUTH_FAILED'),
      'UNSUPPORTED' => PlatformError(
          e.message ?? 'Unsupported operation',
          code: 'UNSUPPORTED'),
      'INVALID_ARGS' => PlatformError(e.message ?? 'Invalid arguments',
          code: 'INVALID_ARGS'),
      _ => PlatformError(
          e.message ?? 'Platform error',
          code: e.code),
    };
  }
}
