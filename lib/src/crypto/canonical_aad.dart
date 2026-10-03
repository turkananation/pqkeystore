// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

import 'dart:convert';
import 'dart:typed_data';

import '../api/key_metadata.dart';

/// Produces a stable, deterministic canonical JSON representation of
/// [metadata], encoded as UTF-8 bytes.
///
/// Keys are sorted alphabetically at the top level. Nested objects
/// (e.g., threshold, tags) are also sorted. This ensures that two
/// [KeyMetadata] instances with identical logical content always
/// produce byte-identical AAD.
///
/// Used by [PqKeystoreCrypto] implementations to bind ciphertext
/// to its associated metadata via Additional Authenticated Data.
Uint8List canonicalAad(KeyMetadata metadata) {
  final map = metadata.toJson();
  final sorted = _sortDeep(map);
  final jsonStr = jsonEncode(sorted);
  return Uint8List.fromList(utf8.encode(jsonStr));
}

/// Recursively sort map keys to ensure deterministic serialization.
dynamic _sortDeep(dynamic value) {
  if (value is Map<String, dynamic>) {
    final sortedKeys = value.keys.toList()..sort();
    return {
      for (final k in sortedKeys) k: _sortDeep(value[k]),
    };
  }
  if (value is List) {
    return value.map(_sortDeep).toList();
  }
  return value;
}
