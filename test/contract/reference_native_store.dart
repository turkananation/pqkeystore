// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Reference implementation of the native side of platform contract v1, in
// pure Dart. This is the executable specification: every native
// implementation (Android, iOS, macOS, Windows, Linux) must behave exactly
// like this for every call in platform_contract_suite.dart.
//
// It is test-only and provides no protection whatsoever.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pqkeystore/pqkeystore.dart';

/// In-memory reference of the native store contract.
final class ReferenceNativeStore {
  ReferenceNativeStore({
    this.os = 'linux',
    this.backend = 'reference-memory',
    Set<String> supportedOptions = const {},
    this.contractVersion = PlatformContract.version,
  }) : supportedOptions = Set.of(supportedOptions);

  final String os;
  final String backend;
  final Set<String> supportedOptions;
  final int contractVersion;
  final Map<String, Uint8List> _entries = {};

  /// Number of calls per method, for assertions about round-trips.
  final Map<String, int> callCounts = {};

  /// Handler suitable for `setMockMethodCallHandler`.
  Future<Object?> handle(MethodCall call) async {
    callCounts.update(call.method, (n) => n + 1, ifAbsent: () => 1);
    switch (call.method) {
      case PlatformContract.methodPlatformInfo:
        return <String, Object>{
          'contractVersion': contractVersion,
          'os': os,
          'backend': backend,
          'supportedOptions': supportedOptions.toList()..sort(),
        };
      case PlatformContract.methodPut:
        final args = _args(call, const {
          PlatformContract.argId,
          PlatformContract.argData,
          PlatformContract.argOptions,
        });
        final id = _id(args);
        final data = args[PlatformContract.argData];
        if (data is! Uint8List ||
            data.isEmpty ||
            data.length > PlatformContract.maxRecordBytes) {
          throw _invalid(
            'data must be 1..${PlatformContract.maxRecordBytes} '
            'bytes',
          );
        }
        _validateOptions(args[PlatformContract.argOptions]);
        _entries[id] = Uint8List.fromList(data);
        return null;
      case PlatformContract.methodGet:
        final id = _id(_args(call, const {PlatformContract.argId}));
        final value = _entries[id];
        return value == null ? null : Uint8List.fromList(value);
      case PlatformContract.methodDelete:
        final id = _id(_args(call, const {PlatformContract.argId}));
        return _entries.remove(id) != null;
      case PlatformContract.methodContains:
        final id = _id(_args(call, const {PlatformContract.argId}));
        return _entries.containsKey(id);
      case PlatformContract.methodListIds:
        if (call.arguments != null) {
          throw _invalid('listIds takes no arguments');
        }
        return _entries.keys.toList();
      default:
        throw MissingPluginException();
    }
  }

  /// Directly overwrites stored bytes (simulates on-disk tampering).
  void tamper(String id, Uint8List bytes) => _entries[id] = bytes;

  static PlatformException _invalid(String message) =>
      PlatformException(code: PlatformErrorCode.invalidArgs, message: message);

  static Map<Object?, Object?> _args(MethodCall call, Set<String> allowed) {
    final args = call.arguments;
    if (args is! Map) {
      throw _invalid('arguments must be a map');
    }
    for (final key in args.keys) {
      if (!allowed.contains(key)) {
        throw _invalid('unexpected argument');
      }
    }
    return args;
  }

  static String _id(Map<Object?, Object?> args) {
    final id = args[PlatformContract.argId];
    if (id is! String ||
        id.isEmpty ||
        id.contains('\u0000') ||
        utf8.encode(id).length > PlatformContract.maxIdUtf8Bytes) {
      throw _invalid('invalid id');
    }
    return id;
  }

  void _validateOptions(Object? raw) {
    if (raw is! Map || raw.length != PlatformContract.optionKeys.length) {
      throw _invalid('options must contain exactly the v1 keys');
    }
    for (final key in PlatformContract.optionKeys) {
      if (!raw.containsKey(key)) {
        throw _invalid('options must contain exactly the v1 keys');
      }
    }
    final presence = raw[PlatformContract.optRequireUserPresence];
    final biometric = raw[PlatformContract.optRequireBiometric];
    final accessibility = raw[PlatformContract.optAccessibility];
    final sync = raw[PlatformContract.optSynchronizable];
    if (presence is! bool || biometric is! bool || sync is! bool) {
      throw _invalid('boolean option has wrong type');
    }
    final requested = <String>{
      if (presence) PlatformContract.capRequireUserPresence,
      if (biometric) PlatformContract.capRequireBiometric,
      if (sync) PlatformContract.capSynchronizable,
    };
    switch (accessibility) {
      case PlatformContract.accessibilityPlatformDefault:
        break;
      case PlatformContract.accessibilityWhenUnlocked:
        requested.add(PlatformContract.capAccessibilityWhenUnlocked);
      case PlatformContract.accessibilityAfterFirstUnlock:
        requested.add(PlatformContract.capAccessibilityAfterFirstUnlock);
      default:
        throw _invalid('unknown accessibility');
    }
    // Order is normative: unsupported capability first, then combinations.
    if (!supportedOptions.containsAll(requested)) {
      throw PlatformException(
        code: PlatformErrorCode.unsupportedOption,
        message: 'option not enforceable on this device',
      );
    }
    if (sync && (presence || biometric)) {
      throw PlatformException(
        code: PlatformErrorCode.unsupportedOption,
        message: 'synchronizable cannot be combined with access control',
      );
    }
  }
}
