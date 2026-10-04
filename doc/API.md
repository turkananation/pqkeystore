# API Reference

This reference describes the API currently exported by `package:pqkeystore/pqkeystore.dart`. It is not a promise that every backend works in production. The constructor currently uses private named parameter identifiers and is not callable by external libraries as intended; see [`BUGS.md`](BUGS.md) BUG-001 and [`TRACKER.md`](TRACKER.md) TRK-002.

## `PqKeystore`

The facade is intended to be constructed from a `PqKeystoreBackend` and `PqKeystoreCrypto`. The constructor visibility defect must be fixed before consumer code can use the intended named-argument form.

### Operations

```dart
Future<KsResult<void>> put(
    KeyMetadata metadata,
    Uint8List plaintext,
    UnlockMethod unlock,
)

Future<KsResult<T>> use<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List plaintext) body,
)

Future<KsResult<void>> delete(KeyId id)

Future<KsResult<List<KeyMetadata>>> list({KeyKind? kind, String? purpose})

Future<KsResult<KeyMetadata>> metadata(KeyId id)

Future<KsResult<void>> putShare(
    KeyMetadata metadata,
    Uint8List shareData,
    UnlockMethod unlock,
)

Future<KsResult<T>> useShare<T>(
    KeyId id,
    UnlockMethod unlock,
    Future<T> Function(Uint8List) body,
)
```

`use` is the preferred access path. Its callback buffer is cleared in a `finally` block and its `SecretBytes` wrapper is disposed. The original unwrap buffer's ownership and complete memory-erasure behavior have not been verified; callers should not retain or copy callback data.

`putShare` checks that `metadata.kind` is `KeyKind.thresholdShare` and that threshold metadata is present. It does not validate threshold values or perform a `pqthreshold` ceremony. `useShare` delegates to `use`.

## Data Types

* `KeyId` wraps an identifier string.
* `KeyKind` classifies key material.
* `KeyMetadata` includes `id`, `kind`, `algorithm`, `createdAt`, and optional `purpose`, `version`, `rotatedFrom`, `threshold`, and `tags`.
* `ThresholdMeta` includes `schemeId`, `t`, `n`, `participantIndex`, `ceremonyId`, and optional `rosterHashHex`.
* `SealedRecord` is the versioned PQKS record persisted by a backend. Its metadata is not secret; confidentiality and authentication depend on the crypto adapter and backend.

## Unlock Types

`UnlockMethod` is sealed and currently has `PassphraseUnlock(Uint8List passphrase)`, `PlatformUnlock()`, and `PassphraseThenPlatform(Uint8List passphrase)`. `PqKeystore.put` rejects `PlatformUnlock` for v1. Platform authentication behavior for the other types is unresolved; see [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md). Do not infer biometric enforcement from the type names.

## Results And Errors

The current API returns local `KsResult<T>`, implemented by `KsSuccess<T>` and `KsFailure<T>`, with a `when(success:, failure:)` method. It is not currently the `swissarmyknife` `Result` type.

Failure types include `NotFound`, `PlatformError`, `CryptoError`, `FormatError`, `Cancelled`, and `PolicyError`, all derived from `PqKeystoreError`. Exact platform error codes depend on backend mappings.

## PQKS Record

The current v1 record contains magic/version framing and length-prefixed wrap algorithm, JSON metadata, AAD, nonce, KDF parameters, and ciphertext. Do not treat parsing as an integrity guarantee. The decoder currently accepts trailing bytes, and metadata-to-AAD consistency is not checked on retrieval; see BUG-005 and BUG-008 in [`BUGS.md`](BUGS.md), and [ADR-0006](adr/0006-pqks-record-invariants.md).
