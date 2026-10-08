# pqkeystore — Android

Native Android implementation of
[platform channel contract v1](../doc/PLATFORM_CONTRACT.md). Every byte is
sealed under a non-exportable AndroidKeyStore key and stored in the app's
*no-backup* directory. Design and limits:
[ADR-0009](../doc/adr/0009-native-backend-designs.md).

## Storage model

| Property | Value |
| --- | --- |
| Key | AES-256-GCM, generated in **AndroidKeyStore**, non-exportable |
| Key aliases | `com.yardenah.pqkeystore.v1.default`, `com.yardenah.pqkeystore.v1.unlocked` |
| Location | `<noBackupFilesDir>/pqkeystore/v1/` |
| File name | `hex(SHA-256(UTF-8 ID)).pqna` |
| Envelope | PQKS record inside a PQNA v2 container, AES-GCM under the key |
| Record size | 1 byte … 1 MiB |
| ID size | 1 … 256 UTF-8 bytes, no U+0000 |

Native code stores **one opaque PQKS blob per ID and nothing else**. It never
parses metadata, never reserves an ID prefix, and never keeps a sidecar: there
is no `__meta__` namespace and no index. `list()` filtering happens in Dart by
decoding each record.

`noBackupFilesDir` is excluded from Auto Backup and device-to-device transfer.
That is deliberate: the AndroidKeyStore key never leaves the device, so a
restored blob would be undecryptable. Excluding it avoids shipping useless
"restored but unreadable" state.

## Why PQNA is chunked (v2)

The record is sealed as **48 KiB chunks**, each with its own GCM IV and its own
tag, concatenated into a single file:

```
header || u8 chunkCount || chunkCount × iv(12) || chunk_0 || chunk_1 || …
```

Each chunk's AAD is `header || u8(chunkIndex)`, so ID, key profile and chunk
position are all authenticated into every tag.

This exists because of a measured platform defect, not a stylistic choice:
AndroidKeyStore AES-GCM on **API 24–28 fails tag verification for payloads
above roughly 64–256 KiB**. A record sealed whole would be written successfully
and then be unreadable. Chunking keeps each AEAD call small and deterministic.
`PQNA` v1 (the unchunked layout) is rejected on read rather than mis-parsed.

## Capabilities

Capabilities are reported **dynamically** in `platformInfo.supportedOptions`,
evaluated at write time on the actual device:

| Option | Offered when | Enforced by |
| --- | --- | --- |
| `accessibility.whenUnlocked` | Device has a secure lock screen **and** API ≥ 28 | `setUnlockedDeviceRequired(true)` |
| `accessibility.afterFirstUnlock` | Device has a secure lock screen **and** per-user file-based encryption is active | Credential-encrypted storage |

Everything else is refused explicitly rather than silently ignored:

- `requireUserPresence`, `requireBiometric` → `UNSUPPORTED_OPTION`. They need a
  `BiometricPrompt` hosted by a `FragmentActivity`, which this plugin
  deliberately does not create. Silently accepting them would over-claim.
- `synchronizable` → `UNSUPPORTED_OPTION`. There is no Android equivalent for
  a keystore record.

If the device is locked, every operation returns `LOCKED` rather than an empty
success, because credential-encrypted storage is unreadable before first unlock.

## Threading

`onAttachedToEngine` creates **one** dedicated single-thread executor. Every
call is validated and executed on it in strict FIFO order and the result is
posted back to the main thread, so the UI thread is never blocked and calls are
never reordered. If a call arrives after detach, it fails fast with
`UNAVAILABLE`.

## Durability and recovery

- Write path: unique temp file in the same directory → `flush` → `fsync` →
  `rename(2)` over the old file → directory `fsync`.
- A crash therefore leaves either the previous valid envelope or a stale
  `.tmp-*` file. The previous valid record is never lost mid-replacement.
- Stale temp files older than 10 minutes are reclaimed once at engine attach,
  which is safe because any write in flight is necessarily younger.
- A file whose payload fails authentication is reported as `CORRUPT`, never as
  absent.

## Error mapping

| Code | Meaning here |
| --- | --- |
| `INVALID_ARGS` | Wrong method, missing/extra key, wrong type, bad ID, empty or oversized data |
| `UNSUPPORTED_OPTION` | An option this device cannot enforce |
| `UNAVAILABLE` | Plugin detached, or AndroidKeyStore unusable |
| `LOCKED` | Storage locked before first unlock |
| `KEY_INVALIDATED` | The protecting keystore key no longer exists (e.g. keystore cleared) — the entry is unrecoverable |
| `CORRUPT` | Header invalid, or the AEAD tag did not verify |
| `STORAGE_ERROR` | Filesystem failure |

A key that is missing on the read path is never silently recreated: it would
produce garbage that fails the tag check anyway, and the honest answer is that
the entry is gone.

## Source map

| File | Role |
| --- | --- |
| `PqKeystorePlugin.kt` | Channel wiring, worker thread, capability reporting |
| `Contract.kt` | Argument/option validation, error codes. Pure Kotlin, no Android APIs |
| `EntryStore.kt` | PQNA v2 file-per-entry store, atomic replace, strict parse |
| `AndroidKeystoreSealer.kt` | AndroidKeyStore AEAD, 48 KiB chunking, key profiles |
| `src/test/…` | JVM unit tests: contract validation + entry store (fake software sealer) |
| `src/androidTest/…` | On-device `OnDeviceRoundTripTest`: real AndroidKeyStore, boundary sizes up to 1 MiB |

`Contract` and `EntryStore` deliberately avoid Android APIs so the bulk of the
logic runs in fast JVM unit tests; only the sealer needs a real device.

## Tests

JVM unit tests (no device required):

```sh
cd example/android
./gradlew :pqkeystore:testDebugUnitTest
```

On-device round trip against the **real** AndroidKeyStore, at the chunk
boundary and at the 1 MiB contract maximum:

```sh
cd example/android
./gradlew :pqkeystore:connectedDebugAndroidTest
```

End-to-end contract suite against the real plugin:

```sh
flutter test integration_test/platform_contract_test.dart -d emulator-5554
```

CI runs all three (see [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)),
on API 26 (minimum), 28 (`setUnlockedDeviceRequired`) and 35 (current).

## What is NOT claimed

- **Hardware backing.** Whether the key lands in a TEE, StrongBox, or software
  depends entirely on the device. This plugin never claims it and never probes
  for it.
- **Per-app isolation.** AndroidKeyStore namespaces keys per UID, but anyone
  with the same app signing identity and the same alias can use them.
- **Biometrics / user presence.** Not offered in v1.
- **Cross-device portability.** Records are device-bound by construction.
- **Post-erasure.** `delete` removes the file; it does not overwrite flash.
