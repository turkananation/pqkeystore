/// # pqkeystore
///
/// Post-quantum key management layer for Dart/Flutter.
///
/// This is the barrel export file — import `package:pqkeystore/pqkeystore.dart`
/// to access the full public API.
///
/// **WARNING**: `StubKeystoreCrypto` is **NOT SECURE** and must never be used
/// in production. It exists solely for structural testing without device
/// dependencies.
library;

export 'src/api/errors.dart';
// ── API ─────────────────────────────────────────────────────────────────
export 'src/api/key_id.dart';
export 'src/api/key_kind.dart';
export 'src/api/key_metadata.dart';
export 'src/api/pq_keystore.dart';
export 'src/api/sealed_record.dart';
export 'src/api/unlock.dart';
// ── Backend ─────────────────────────────────────────────────────────────
export 'src/backend/backend.dart';
export 'src/backend/backend_factory.dart';
export 'src/backend/fallback_keystore_backend.dart';
export 'src/backend/file_keystore_backend.dart';
export 'src/backend/memory_keystore_backend.dart';
export 'src/backend/platform_contract.dart';
export 'src/backend/platform_keystore_backend.dart';
export 'src/backend/platform_options.dart';
// ── Crypto ──────────────────────────────────────────────────────────────
export 'src/crypto/canonical_aad.dart';
export 'src/crypto/keystore_crypto.dart';
export 'src/crypto/pq_forge_keystore_crypto.dart';
export 'src/crypto/stub_keystore_crypto.dart';
