// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Attacker-controlled Argon2id costs live in a stored record. Reject them
// before any KDF allocation. These bounds match pqforge's Argon2Limits
// (0.4.7 through 0.4.13) except salt length, which this package floors at
// 16 bytes — the salt `PqForgeKeystoreCrypto` actually writes — rather than
// pqforge's provider floor of 8.

import 'dart:convert';
import 'dart:typed_data';

import '../api/errors.dart';

/// Minimum Argon2id iterations. Inclusive.
const int argon2idMinIterations = 1;

/// Maximum Argon2id iterations. Inclusive.
const int argon2idMaxIterations = 10;

/// Minimum `memoryPowerOf2` (`2^n` KiB). 2^10 KiB = 1 MiB.
const int argon2idMinMemoryPowerOf2 = 10;

/// Maximum `memoryPowerOf2`. 2^20 KiB = 1 GiB.
const int argon2idMaxMemoryPowerOf2 = 20;

/// Minimum Argon2id lanes. Inclusive.
const int argon2idMinLanes = 1;

/// Maximum Argon2id lanes. Inclusive.
const int argon2idMaxLanes = 16;

/// Minimum salt length. Stricter than pqforge's 8-byte provider floor.
const int argon2idMinSaltBytes = 16;

/// The only KDF id v1 will feed to `pqforge`.
const String argon2idKdfId = 'argon2id';

/// The only AEAD id v1 will feed to `pqforge`.
const String argon2idAeadId = 'aes-256-gcm';

/// Checks stored KDF parameters before they can reach a password KDF.
///
/// Returns `null` when [params] is null and [saltRequired] is false (the
/// test-fixture shape, which carries no KDF block). Otherwise returns a
/// [FormatError] naming the parameter, the observed value, and the permitted
/// range. Never returns [CryptoError]: a hostile record is malformed input,
/// not a failed decryption.
///
/// Absent numeric fields are accepted. The caller applies an in-range default.
/// A present field of the wrong JSON type is rejected rather than coerced.
FormatError? validateStoredArgon2idParams(
  Map<String, dynamic>? params, {
  required bool saltRequired,
}) {
  if (params == null) {
    if (!saltRequired) {
      return null;
    }
    return const FormatError(
      'kdfParams are required and must include a salt of at least '
      '$argon2idMinSaltBytes bytes',
    );
  }

  final kdf = params['kdf'];
  if (kdf != null && kdf != argon2idKdfId) {
    return const FormatError(
      'kdf is not permitted; v1 allows only $argon2idKdfId',
    );
  }
  final aead = params['aead'];
  if (aead != null && aead != argon2idAeadId) {
    return const FormatError(
      'aead is not permitted; v1 allows only $argon2idAeadId',
    );
  }

  final iterations = _optionalInt(
    params,
    'iterations',
    argon2idMinIterations,
    argon2idMaxIterations,
  );
  if (iterations != null) {
    return iterations;
  }
  final memory = _optionalInt(
    params,
    'memoryPowerOf2',
    argon2idMinMemoryPowerOf2,
    argon2idMaxMemoryPowerOf2,
  );
  if (memory != null) {
    return memory;
  }
  final lanes = _optionalInt(
    params,
    'lanes',
    argon2idMinLanes,
    argon2idMaxLanes,
  );
  if (lanes != null) {
    return lanes;
  }

  return _checkSalt(params, required: saltRequired);
}

/// Programmer-supplied wrap costs. Same numeric window as stored params.
///
/// Returns `null` when every argument is inside the permitted range.
FormatError? validateChosenArgon2idCost({
  required int iterations,
  required int memoryPowerOf2,
  required int lanes,
}) {
  if (iterations < argon2idMinIterations ||
      iterations > argon2idMaxIterations) {
    return FormatError(
      'iterations $iterations is outside the permitted range '
      '$argon2idMinIterations..$argon2idMaxIterations',
    );
  }
  if (memoryPowerOf2 < argon2idMinMemoryPowerOf2 ||
      memoryPowerOf2 > argon2idMaxMemoryPowerOf2) {
    return FormatError(
      'memoryPowerOf2 $memoryPowerOf2 is outside the permitted range '
      '$argon2idMinMemoryPowerOf2..$argon2idMaxMemoryPowerOf2',
    );
  }
  if (lanes < argon2idMinLanes || lanes > argon2idMaxLanes) {
    return FormatError(
      'lanes $lanes is outside the permitted range '
      '$argon2idMinLanes..$argon2idMaxLanes',
    );
  }
  return null;
}

FormatError? _optionalInt(
  Map<String, dynamic> params,
  String name,
  int min,
  int max,
) {
  if (!params.containsKey(name) || params[name] == null) {
    return null;
  }
  final value = params[name];
  if (value is! int) {
    return FormatError(
      '$name must be an int in the permitted range $min..$max',
    );
  }
  if (value < min || value > max) {
    return FormatError(
      '$name $value is outside the permitted range $min..$max',
    );
  }
  return null;
}

FormatError? _checkSalt(Map<String, dynamic> params, {required bool required}) {
  final raw = params['salt'];
  if (raw == null) {
    if (!required) {
      return null;
    }
    return const FormatError(
      'salt is required and must decode to at least '
      '$argon2idMinSaltBytes bytes',
    );
  }
  if (raw is! String || raw.isEmpty) {
    return const FormatError(
      'salt must be a non-empty base64 string of at least '
      '$argon2idMinSaltBytes bytes',
    );
  }
  final Uint8List decoded;
  try {
    decoded = base64Decode(raw);
  } on FormatException {
    return const FormatError(
      'salt must be a non-empty base64 string of at least '
      '$argon2idMinSaltBytes bytes',
    );
  }
  if (decoded.length < argon2idMinSaltBytes) {
    return FormatError(
      'salt length ${decoded.length} is outside the permitted range '
      '$argon2idMinSaltBytes..',
    );
  }
  return null;
}
