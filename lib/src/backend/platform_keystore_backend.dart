// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform backend — delegates to OS-level secure storage via MethodChannel.
//
// Implements platform channel contract v1 (doc/PLATFORM_CONTRACT.md).
// Native code stores one opaque PQKS blob per ID — nothing else. Metadata
// used for list filtering is decoded from the PQKS record itself, so every
// write is a single atomic native operation and no ID prefix is reserved.

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../api/errors.dart';
import '../api/key_id.dart';
import '../api/key_kind.dart';
import '../api/sealed_record.dart';
import 'backend.dart';
import 'platform_contract.dart';
import 'platform_options.dart';

/// Backend that delegates to OS-level secure storage via [MethodChannel].
///
/// | Platform | Mechanism (see doc/PLATFORM.md for limits)                     |
/// |----------|----------------------------------------------------------------|
/// | Android  | AES-256-GCM under an AndroidKeyStore key; files in noBackup dir |
/// | iOS      | Keychain generic password (data protection keychain)           |
/// | macOS    | Keychain generic password (data protection keychain)           |
/// | Windows  | DPAPI (user scope) protected files under %LOCALAPPDATA%        |
/// | Linux    | Secret Service via libsecret; no file fallback                 |
///
/// The first operation performs a `platformInfo` handshake and fails with
/// [PlatformErrorCode.contractMismatch] if the native side implements a
/// different contract version.
final class PlatformKeystoreBackend implements PqKeystoreBackend {
  /// Creates a [PlatformKeystoreBackend] with optional write [options].
  PlatformKeystoreBackend({
    this.options = const PlatformStoreOptions(),
    @visibleForTesting MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(PlatformContract.channelName);

  final MethodChannel _channel;

  /// Storage policy applied to every write performed by this backend.
  final PlatformStoreOptions options;

  Future<PlatformInfo>? _info;

  /// Returns the native [PlatformInfo], performing the handshake once.
  ///
  /// A failed handshake is not cached, so a later call can retry.
  Future<PlatformInfo> platformInfo() {
    return _info ??= _handshake().catchError((Object e) {
      _info = null;
      throw e;
    });
  }

  Future<PlatformInfo> _handshake() async {
    final raw = await _invoke<Object?>(PlatformContract.methodPlatformInfo);
    return PlatformInfo.fromChannel(raw);
  }

  /// Lists every stored ID, sorted by UTF-16 code units.
  ///
  /// Useful for recovering from a [PlatformErrorCode.corrupt] entry, which
  /// can be removed with [delete] without decoding it.
  Future<List<String>> listIds() async {
    await platformInfo();
    final raw = await _invoke<Object?>(PlatformContract.methodListIds);
    if (raw is! List) {
      throw _contractViolation('listIds did not return a list');
    }
    final ids = <String>[];
    for (final id in raw) {
      if (id is! String) {
        throw _contractViolation('listIds returned a non-string');
      }
      ids.add(id);
    }
    return ids..sort();
  }

  @override
  Future<void> putSealed(KeyId id, SealedRecord record) async {
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

    options.validateCombination();
    final info = await platformInfo();
    final missing = options.requiredCapabilities.difference(
      info.supportedOptions,
    );
    if (missing.isNotEmpty) {
      throw PlatformError(
        '${info.os} cannot enforce: ${(missing.toList()..sort()).join(', ')}',
        code: PlatformErrorCode.unsupportedOption,
      );
    }

    await _invoke<void>(PlatformContract.methodPut, {
      PlatformContract.argId: id.value,
      PlatformContract.argData: encoded,
      PlatformContract.argOptions: options.toChannelMap(),
    });
  }

  @override
  Future<SealedRecord?> getSealed(KeyId id) async {
    validatePlatformKeyId(id);
    await platformInfo();
    final raw = await _invoke<Object?>(PlatformContract.methodGet, {
      PlatformContract.argId: id.value,
    });
    if (raw == null) {
      return null;
    }
    if (raw is! Uint8List) {
      throw _contractViolation('get did not return bytes');
    }
    final SealedRecord record;
    try {
      record = SealedRecord.decode(Uint8List.fromList(raw));
    } on PqKeystoreError {
      rethrow;
    } catch (_) {
      throw FormatError('stored record for $id is not valid PQKS');
    }
    // Identity binding (ADR-0003/0006): a record must only be returned for
    // the ID it was written under.
    if (record.metadata.id != id) {
      throw FormatError('stored record for $id carries a different ID');
    }
    return record;
  }

  @override
  Future<bool> delete(KeyId id) async {
    validatePlatformKeyId(id);
    await platformInfo();
    final raw = await _invoke<Object?>(PlatformContract.methodDelete, {
      PlatformContract.argId: id.value,
    });
    if (raw is! bool) {
      throw _contractViolation('delete did not return a bool');
    }
    return raw;
  }

  @override
  Future<bool> contains(KeyId id) async {
    validatePlatformKeyId(id);
    await platformInfo();
    final raw = await _invoke<Object?>(PlatformContract.methodContains, {
      PlatformContract.argId: id.value,
    });
    if (raw is! bool) {
      throw _contractViolation('contains did not return a bool');
    }
    return raw;
  }

  /// Lists records, filtering on metadata decoded from each PQKS record.
  ///
  /// Each record is read individually. On platforms where records are
  /// protected by user presence or biometrics this may prompt once per
  /// record. Records deleted concurrently are skipped; any other failure
  /// (including a corrupt entry) is propagated rather than hidden.
  @override
  Future<List<SealedRecord>> list({KeyKind? kind, String? purpose}) async {
    final records = <SealedRecord>[];
    for (final rawId in await listIds()) {
      final id = KeyId(rawId);
      try {
        validatePlatformKeyId(id);
      } on PlatformError {
        throw _contractViolation('listIds returned an invalid ID');
      }
      final record = await getSealed(id);
      if (record == null) {
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
    return records;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } on MissingPluginException {
      throw const PlatformError(
        'pqkeystore native plugin is not registered on this platform',
        code: PlatformErrorCode.unavailable,
      );
    }
  }

  static PlatformError _contractViolation(String why) => PlatformError(
    'native result violates contract v${PlatformContract.version}: $why',
    code: PlatformErrorCode.contractMismatch,
  );

  /// Maps a native [PlatformException] to a [PqKeystoreError].
  ///
  /// Native messages are contract-bound to never contain secret material;
  /// `details` is ignored.
  @visibleForTesting
  static PqKeystoreError mapPlatformException(PlatformException e) {
    if (e.code == PlatformErrorCode.userCancelled) {
      return const Cancelled();
    }
    final code = PlatformErrorCode.nativeCodes.contains(e.code)
        ? e.code
        : PlatformErrorCode.storageError;
    return PlatformError(e.message ?? 'Platform error', code: code);
  }
}
