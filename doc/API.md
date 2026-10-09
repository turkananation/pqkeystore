# API Reference

This reference describes the API currently exported by `package:pqkeystore/pqkeystore.dart`. It is not a promise that every backend works in production. Public construction with `PqKeystore(backend: ..., crypto: ...)` compiles and is covered by the facade tests. The example app itself remains simulated; see TRK-013 in [`TRACKER.md`](TRACKER.md).

## `PqKeystore`

Construct the facade from a `PqKeystoreBackend` and `PqKeystoreCrypto`:

```dart
final keystore = PqKeystore(backend: backend, crypto: crypto);
```

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
  `participantIndex` is **1-based**, matching `pqthreshold.Share.index`. `putShare`
  validates `1 <= t <= n`, `participantIndex` in `1..n`, and a non-empty
  `ceremonyId`, returning `PolicyError` before the backend is touched.
* `SealedRecord` is the versioned PQKS record persisted by a backend. PQKS serializes metadata in cleartext; deployments should treat purpose, tags, threshold details, and identifiers as potentially sensitive. Backend protection varies.

## Unlock Types

`UnlockMethod` is sealed and currently has `PassphraseUnlock(Uint8List passphrase)`, `PlatformUnlock()`, and `PassphraseThenPlatform(Uint8List passphrase)`. `PqKeystore.put` rejects `PlatformUnlock` for v1. Platform authentication behavior for the other types is unresolved; see [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md). Do not infer biometric enforcement from the type names.

## Platform Backend

```dart
final backend = PlatformKeystoreBackend(
  options: const PlatformStoreOptions(
    accessibility: PlatformAccessibility.whenUnlocked,
  ),
);
final info = await backend.platformInfo(); // os, backend, supportedOptions
```

* `PlatformStoreOptions({requireUserPresence, requireBiometric, accessibility, synchronizable})`. The defaults request nothing extra and are accepted on all five platforms. Each non-default value must appear in `info.supportedOptions`; otherwise writes fail with `PlatformError(code: 'UNSUPPORTED_OPTION')`. `synchronizable` cannot be combined with user presence or biometrics.
* `PlatformAccessibility`: `platformDefault`, `whenUnlocked`, `afterFirstUnlock`.
* Platform IDs are 1 to 256 UTF-8 bytes, contain no U+0000, and are compared exactly. Records are at most 1 MiB.
* `listIds()` returns every stored ID and is useful for removing a `CORRUPT` entry with `delete`.

## Fallback And File Backends

```dart
final files = FileKeystoreBackend(Directory(path));              // layout v1
final fallback = FallbackKeystoreBackend(
  secure: PlatformKeystoreBackend(),
  fallback: files,
  onFallback: (reason) { /* surface to the app */ },
);
```

`FileKeystoreBackend` writes one `<sha256(id)>.pqks` file per record into a dedicated directory (`0700`/`0600` on desktop POSIX), with no index and no sanitized names. `FallbackKeystoreBackend` only diverts to the file store when the platform store reports `UNAVAILABLE`, replays tombstones when the platform store returns, and removes fallback copies once a secure write succeeds. Details: [`PLATFORM.md`](PLATFORM.md), [`FORMATS.md`](FORMATS.md), [ADR-0010](adr/0010-file-fallback-and-recovery.md).
* Error codes are listed in `PlatformErrorCode`. `USER_CANCELLED` surfaces as `Cancelled`; all other codes surface as `PlatformError.code`. See [`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md) and [`PLATFORM.md`](PLATFORM.md).

## Results And Errors

The current API returns local `KsResult<T>`, implemented by `KsSuccess<T>` and `KsFailure<T>`, with a `when(success:, failure:)` method. It is not currently the `swissarmyknife` `Result` type.

Failure types include `NotFound`, `PlatformError`, `CryptoError`, `FormatError`, `Cancelled`, and `PolicyError`, all derived from `PqKeystoreError`. Platform error codes are the closed set in `PlatformErrorCode` ([`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md) §6).

## PQKS Record

The current v1 record contains magic/version framing and length-prefixed wrap algorithm, JSON metadata, AAD, nonce, KDF parameters, and ciphertext. Do not treat parsing as an integrity guarantee. The decoder currently accepts trailing bytes, and metadata-to-AAD consistency is not checked on retrieval; see BUG-005 and BUG-008 in [`BUGS.md`](BUGS.md), and [ADR-0006](adr/0006-pqks-record-invariants.md).

## PQKS And pqforge Envelopes

These formats have different owners and jobs; they are not interchangeable:

| Format | Purpose |
| --- | --- |
| PQKS | `pqkeystore`'s versioned persisted record: key metadata plus the selected crypto wrapper's parameters and ciphertext. |
| `PqWrappedKey` | pqforge's passphrase-wrapped exported key: KDF/AEAD, salt, nonce, ciphertext, and authenticated key identity. `PqForgeKeystoreCrypto` currently maps its fields into PQKS. |
| `.pqf` / `PqEnvelope` | pqforge's one-shot, recipient-oriented content envelope using KEM-derived encryption. Not used as a keystore record. |
| `.pqfs` / `PqStreamingEnvelope` | pqforge's framed streaming content envelope for large data. Not used as a keystore record. |

The `.pqf` suffix is not the raw binary magic; the envelope codec uses a length-prefixed `PQF1` field. `.pqfs` uses its own `PQFS` streaming frame. V1 promises no `.pqf`/`.pqfs` import/export interoperability. See [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md).
