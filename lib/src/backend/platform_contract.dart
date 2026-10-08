// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform channel contract v1 — the single source of truth on the Dart side.
//
// The normative specification lives in doc/PLATFORM_CONTRACT.md. Every
// constant here MUST match the five native implementations byte-for-byte
// (Android, iOS, macOS, Windows, Linux). Changing any value is a contract
// version bump.

import 'dart:convert';

import '../api/errors.dart';
import '../api/key_id.dart';

/// Constants for the native storage channel contract.
///
/// This is a namespace of constants, intentionally not instantiable.
// ignore: avoid_classes_with_only_static_members
abstract final class PlatformContract {
  /// Frozen MethodChannel name, identical on all five platforms.
  static const String channelName = 'com.yardenah.pqkeystore/store';

  /// Contract version implemented by this Dart client.
  ///
  /// Native implementations report their version from `platformInfo`; the
  /// client refuses to operate on a mismatch.
  static const int version = 1;

  /// Maximum UTF-8 encoded length of a storage ID, in bytes.
  static const int maxIdUtf8Bytes = 256;

  /// Maximum size of a stored record, in bytes (1 MiB).
  static const int maxRecordBytes = 1024 * 1024;

  // ── Methods ────────────────────────────────────────────────────────────
  static const String methodPlatformInfo = 'platformInfo';
  static const String methodPut = 'put';
  static const String methodGet = 'get';
  static const String methodDelete = 'delete';
  static const String methodContains = 'contains';
  static const String methodListIds = 'listIds';

  // ── Argument keys ──────────────────────────────────────────────────────
  static const String argId = 'id';
  static const String argData = 'data';
  static const String argOptions = 'options';

  // ── Option keys (all four are required inside `options`) ───────────────
  static const String optRequireUserPresence = 'requireUserPresence';
  static const String optRequireBiometric = 'requireBiometric';
  static const String optAccessibility = 'accessibility';
  static const String optSynchronizable = 'synchronizable';

  /// The complete, closed set of option keys. Natives reject any other key.
  static const Set<String> optionKeys = {
    optRequireUserPresence,
    optRequireBiometric,
    optAccessibility,
    optSynchronizable,
  };

  // ── Accessibility values ───────────────────────────────────────────────
  static const String accessibilityPlatformDefault = 'platformDefault';
  static const String accessibilityWhenUnlocked = 'whenUnlocked';
  static const String accessibilityAfterFirstUnlock = 'afterFirstUnlock';

  // ── Capability names reported in `platformInfo.supportedOptions` ───────
  static const String capRequireUserPresence = 'requireUserPresence';
  static const String capRequireBiometric = 'requireBiometric';
  static const String capAccessibilityWhenUnlocked =
      'accessibility.whenUnlocked';
  static const String capAccessibilityAfterFirstUnlock =
      'accessibility.afterFirstUnlock';
  static const String capSynchronizable = 'synchronizable';

  /// The complete, closed set of capability names.
  static const Set<String> capabilities = {
    capRequireUserPresence,
    capRequireBiometric,
    capAccessibilityWhenUnlocked,
    capAccessibilityAfterFirstUnlock,
    capSynchronizable,
  };

  /// Valid values reported in `platformInfo.os`.
  static const Set<String> osNames = {
    'android',
    'ios',
    'macos',
    'windows',
    'linux',
  };
}

/// Stable error codes carried in `PlatformException.code` and
/// [PlatformError.code].
// ignore: avoid_classes_with_only_static_members
abstract final class PlatformErrorCode {
  /// Arguments are missing, of the wrong type, or out of range.
  static const String invalidArgs = 'INVALID_ARGS';

  /// A requested option (or option combination) cannot be enforced here.
  static const String unsupportedOption = 'UNSUPPORTED_OPTION';

  /// The OS storage facility is not available (e.g. no Secret Service, no
  /// keychain entitlement, plugin not registered).
  static const String unavailable = 'UNAVAILABLE';

  /// Storage is present but locked (device locked, collection locked).
  static const String locked = 'LOCKED';

  /// The user dismissed an authentication or unlock prompt.
  static const String userCancelled = 'USER_CANCELLED';

  /// The user failed authentication.
  static const String authFailed = 'AUTH_FAILED';

  /// The protecting OS key was permanently invalidated (e.g. biometric set
  /// changed, lock screen removed). The record is unrecoverable.
  static const String keyInvalidated = 'KEY_INVALIDATED';

  /// A stored entry exists but cannot be decoded or authenticated.
  static const String corrupt = 'CORRUPT';

  /// Any other OS or I/O failure.
  static const String storageError = 'STORAGE_ERROR';

  /// Dart-only: native side reports a different contract version.
  static const String contractMismatch = 'CONTRACT_MISMATCH';

  /// All codes a native implementation may emit.
  static const Set<String> nativeCodes = {
    invalidArgs,
    unsupportedOption,
    unavailable,
    locked,
    userCancelled,
    authFailed,
    keyInvalidated,
    corrupt,
    storageError,
  };
}

/// Validates [id] against the v1 platform ID rules.
///
/// Rules (see doc/PLATFORM_CONTRACT.md §3):
/// - non-empty;
/// - well-formed UTF-16 (no unpaired surrogates — these would be replaced
///   with U+FFFD in transit and silently alias other IDs);
/// - no U+0000;
/// - at most [PlatformContract.maxIdUtf8Bytes] bytes when UTF-8 encoded.
///
/// IDs are compared exactly; no Unicode normalization or case folding is
/// applied. Throws [PlatformError] with code [PlatformErrorCode.invalidArgs].
void validatePlatformKeyId(KeyId id) {
  final value = id.value;
  if (value.isEmpty) {
    throw const PlatformError(
      'KeyId must not be empty',
      code: PlatformErrorCode.invalidArgs,
    );
  }
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit == 0) {
      throw const PlatformError(
        'KeyId must not contain U+0000',
        code: PlatformErrorCode.invalidArgs,
      );
    }
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final hasLow =
          i + 1 < value.length &&
          value.codeUnitAt(i + 1) >= 0xDC00 &&
          value.codeUnitAt(i + 1) <= 0xDFFF;
      if (!hasLow) {
        throw const PlatformError(
          'KeyId contains an unpaired surrogate',
          code: PlatformErrorCode.invalidArgs,
        );
      }
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const PlatformError(
        'KeyId contains an unpaired surrogate',
        code: PlatformErrorCode.invalidArgs,
      );
    }
  }
  if (utf8.encode(value).length > PlatformContract.maxIdUtf8Bytes) {
    throw const PlatformError(
      'KeyId exceeds ${PlatformContract.maxIdUtf8Bytes} UTF-8 bytes',
      code: PlatformErrorCode.invalidArgs,
    );
  }
}

/// Information reported by the native implementation via `platformInfo`.
final class PlatformInfo {
  /// Creates a [PlatformInfo].
  const PlatformInfo({
    required this.contractVersion,
    required this.os,
    required this.backend,
    required this.supportedOptions,
  });

  /// Parses and strictly validates a `platformInfo` channel result.
  ///
  /// Throws [PlatformError] with [PlatformErrorCode.contractMismatch] when the
  /// shape does not match contract v1.
  factory PlatformInfo.fromChannel(Object? raw) {
    PlatformError mismatch(String why) => PlatformError(
      'platformInfo does not match contract v${PlatformContract.version}: '
      '$why',
      code: PlatformErrorCode.contractMismatch,
    );

    if (raw is! Map) {
      throw mismatch('result is not a map');
    }
    final version = raw['contractVersion'];
    final os = raw['os'];
    final backend = raw['backend'];
    final options = raw['supportedOptions'];
    if (version is! int) {
      throw mismatch('contractVersion missing');
    }
    if (version != PlatformContract.version) {
      throw mismatch('native reports version $version');
    }
    if (os is! String || !PlatformContract.osNames.contains(os)) {
      throw mismatch('unknown os');
    }
    if (backend is! String || backend.isEmpty) {
      throw mismatch('backend missing');
    }
    if (options is! List) {
      throw mismatch('supportedOptions missing');
    }
    final parsed = <String>{};
    for (final option in options) {
      if (option is! String ||
          !PlatformContract.capabilities.contains(option)) {
        throw mismatch('unknown capability');
      }
      parsed.add(option);
    }
    return PlatformInfo(
      contractVersion: version,
      os: os,
      backend: backend,
      supportedOptions: Set.unmodifiable(parsed),
    );
  }

  /// Contract version implemented by the native side.
  final int contractVersion;

  /// One of `android`, `ios`, `macos`, `windows`, `linux`.
  final String os;

  /// Short identifier of the native storage mechanism, for diagnostics only.
  final String backend;

  /// Capability names the native side can enforce *on this device right now*.
  final Set<String> supportedOptions;

  @override
  String toString() =>
      'PlatformInfo(v$contractVersion, $os, $backend, $supportedOptions)';
}
