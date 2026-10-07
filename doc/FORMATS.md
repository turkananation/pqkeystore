# On-Disk Formats

This document is the single reference for every byte layout `pqkeystore` reads or writes. If code and prose disagree, code is wrong or this document needs a version bump.

| Format | Magic | Extension | Written by | Contains | Portable |
| --- | --- | --- | --- | --- | --- |
| PQKS record (§1–§2) | `PQKS` | `.pqks` | Dart `SealedRecord.encode()` | metadata + wrapped-key params + ciphertext | Yes |
| PQNA envelope (§3) | `PQNA` | `.pqna` | Android plugin | one PQKS record, AES-GCM under AndroidKeyStore | No — Android only |
| PQNW envelope (§4) | `PQNW` | `.pqnw` | Windows plugin | one PQKS record, DPAPI | No — Windows only |
| File store (§5) | — (raw `.pqks` files) | `.pqks` | `FileKeystoreBackend` | raw PQKS records | Yes (same record bytes) |
| Darwin keychain item (§7) | n/a (OS-managed) | n/a | iOS/macOS plugin | raw PQKS in `kSecValueData` | No (keychain is per-device) |
| Secret Service item (§8) | n/a (service-managed) | n/a | Linux plugin | base64(PQKS) in the item secret | No |
| Tombstones (§6) | — (JSON) | `.deleted` | `FallbackKeystoreBackend` | a deleted ID, JSON `{"v":1,"id":...}` | No |

Golden rules:

1. **PQKS is the only portable record.** Everything else is an OS-specific envelope around it or a raw store of it.
2. File names never contain the ID: `hex(SHA-256(UTF-8 ID))`. IDs are always read back from the file's own header/record, and a record whose embedded ID does not match its location is not an entry.
3. Every format has a magic, a version byte, and strict framing: unexpected trailing bytes, unknown versions, or overlong fields are rejected.
4. No format is ever parsed by suffix alone.

All integers are big-endian. `u32` length prefixes count bytes, not elements.

## 1. PQKS record (v1)

Byte-for-byte copy of `lib/src/api/sealed_record.dart` as of this document's version.

```
 0  "PQKS"                                    magic (4)
 4  version                                  u32, currently 1
 8  wrapAlg length                           u32
    wrapAlg bytes                            UTF-8
    metadata length                          u32
    metadata JSON                            UTF-8, KeyMetadata.toJson()
    aad length                               u32
    aad bytes
    nonce length (0 allowed)                 u32
    nonce bytes
    kdfParams length (0 allowed)             u32
    kdfParams JSON                           UTF-8, may be null/empty
    ciphertext length                        u32
    ciphertext bytes
```

Invariants enforced by the decoder: magic `PQKS`, known version, all length prefixes in range, UTF-8 fields valid, ciphertext length ≥ 0, and **the parser must end exactly at the last byte** (trailing garbage is rejected). The stored `metadata.id` binds the record to its storage ID (checked by backends and the facade).

`wrapAlg` + `kdfParams` describe the crypto-provider payload (ADR-0007): for `PqForgeKeystoreCrypto` today it is `pqforge-argon2id-aes-256-gcm-v1`.

## 2. File name and identity (all file backends)

```
file name = lowercase hex( SHA-256( UTF-8 bytes of KeyId ) ) + extension
```

- Injective: two different IDs cannot produce the same name (except via a SHA-256 collision).
- Safe on case-insensitive filesystems (NTFS/APFS default), path separators and reserved device names (`CON`, `NUL`, `..`) are impossible because only `[0-9a-f]` and the extension occur.
- The ID itself is recovered from the file content and cross-checked, never derived from the name.

## 3. PQNA envelope (Android)

One envelope per record, stored under the app's *no-backup* files directory (excluded from Auto Backup and device-to-device transfer):

```
 0  "PQNA"                                    magic (4)
 4  format version                            u8, currently 1
 5  key profile                               u8: 0 = DEVICE_DEFAULT, 1 = UNLOCKED_DEVICE_REQUIRED
 6  id length                                 u16
    id bytes                                  UTF-8
    iv length                                 u8 (12 for AES-GCM)
    iv bytes
    ciphertext+tag                            AES-256-GCM(record, key = AndroidKeyStore AES-256, AAD = the header bytes above)
```

- Key: non-exportable AES-256 generated in AndroidKeyStore. `DEVICE_DEFAULT` is the default (`PlatformStoreOptions` defaults); `UNLOCKED_DEVICE_REQUIRED` (`setUnlockedDeviceRequired`, API 28+, secure lock screen) backs `accessibility: whenUnlocked` on devices that claim that capability.
- The AAD is the header (magic through IV-length byte), so the key profile and ID are authenticated. The IV is covered implicitly: any IV modification fails the GCM tag check.
- Atomicity: temp file → `fsync` → `rename(2)` over the old file → directory `fsync`. A crash leaves the old envelope intact or a stale `.tmp-*` file, which is ignored and reclaimed.
- A `.pqna` file cannot be decrypted on another device/profile: the AndroidKeyStore key is non-exportable. That is intentional (ADR-0009).

## 4. PQNW envelope (Windows)

```
 0  "PQNW"                                    magic (4)
 4  format version                            u8, currently 1
 5  id length                                 u16 (id_len)
 7  id bytes                                  UTF-8 (id_len bytes)
 7+id_len  blob length                        u32, bytes of the DPAPI output
    blob                                      CryptProtectData(record) output
```

- DPAPI with `CRYPTPROTECT_UI_FORBIDDEN`, entropy =
  `"com.yardenah.pqkeystore.v1" \0 <app> \0 <id>` where `<app>` is the executable stem (`[A-Za-z0-9._-]`, max 64 chars, else `unknown`) and `<id>` is the record's ID. The entropy binds each blob to its app and location.
- Location: `%LOCALAPPDATA%\yardenah\pqkeystore\<app>\v1\<hexname>.pqnw`, accessed with `\\?\` long paths. Directories are restricted with a protected DACL (current user + SYSTEM).
- Atomicity: unique temp file in the same directory → `FlushFileBuffers` → `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`, with retry on transient sharing violations (antivirus). Readers open with `FILE_SHARE_DELETE`.
- Decryptable only by the same Windows user on the same profile; any process running as that user can decrypt. Documented non-claim.

## 5. Darwin keychain item (iOS / macOS)

There is no custom binary format: the PQKS record is stored as-is in a generic-password keychain item, and the keychain itself owns the on-disk representation (`keychain-*` database in the protected keychain directory; not part of the app container). Fields set by the plugin:

| Attribute | Value |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `com.yardenah.pqkeystore.v1` (pending items use `com.yardenah.pqkeystore.v1.pending` during replacement) |
| `kSecAttrAccount` | the storage ID (UTF-8) |
| `kSecValueData` | the raw PQKS record bytes |
| `kSecAttrAccessible` | `WhenUnlockedThisDeviceOnly` (default), `AfterFirstUnlockThisDeviceOnly`, or the non-`ThisDeviceOnly` variant when `synchronizable` is requested |
| `kSecAttrAccessControl` | set instead of the class when `requireUserPresence` / `requireBiometric` is requested (`.userPresence`, `.biometryCurrentSet`) |
| `kSecAttrSynchronizable` | true only when requested; on macOS also selects the iCloud path |
| `kSecUseDataProtectionKeychain` | always true (macOS); legacy file keychain is never used |

An item is "present" iff an item with that service/account exists. Reading it returns the raw PQKS record, which is then parsed with the same strict decoder (§1), including the embedded-ID check.

## 6. Linux Secret Service item

There is no chosen binary format: the PQKS record is stored in a Secret Service item; the provider owns the on-disk encoding:

| Field | Value |
| --- | --- |
| Schema | `com.yardenah.pqkeystore.v1` (`SECRET_SCHEMA_NONE`) |
| Attributes | `app` = application ID from `GApplication` / `prgname` (fallback `unknown`); `id` = the storage ID |
| Label | `pqkeystore record` (never contains the ID) |
| Secret | canonical base64 of the PQKS record, `ContentType=text/plain` |
| Collection | the provider's default collection (typically `login`) |

Existence = an attribute match for `{app, id}`. Reads return the base64 secret, which is strictly decoded (rejecting non-canonical base64) and parsed with the strict PQKS decoder, including the embedded-ID check. No unsigned fallback: if the service is unreachable every call fails with `UNAVAILABLE`.

## 7. File store v1 (`FileKeystoreBackend`)

Directory layout:

```
<dir>/
  .pqkeystore-layout     marker file, exact content below
  <hexname>.pqks         one per record: the PQKS record, exactly
  *.pqks.tmp-*           incomplete writes; ignored, reclaimed after 10 min
  .tombstones/           (only when used by FallbackKeystoreBackend) see §6
```

`.pqkeystore-layout` content: the single line `pqkeystore-file-store-v1` plus `\n`. If the marker exists with different content, the directory is refused (`FormatError`).

- On first use with no marker, the backend *adopts* the pre-v1 layout in place: sanitized names are re-encoded to §2 names, `.pqks-index.json` is discarded, and the marker is written. Undecodable entries are left untouched.
- Permissions: on desktop POSIX the directory is created `0700` and files `0600`, and the effective mode is verified after `chmod`; failure → `STORAGE_ERROR`. On mobile app sandboxes and Windows the OS ACL provides the isolation that the chmod equivalent provides elsewhere.
- No index file: `list()`/`contains()` derive truth from the directory entries themselves, cross-checked against the embedded ID. (The old unkeyed FNV index is gone; see ADR-0010.)
- A `.pqks` file containing anything that is not a valid PQKS record is not an entry: it is invisible to `list`/`contains`/`get` for its ID, and it is overwritten on the next `put` for that ID.

## 8. Tombstones (`FallbackKeystoreBackend`)

When the secure store reports `UNAVAILABLE` during `delete`, the tombstone records that deletion so the secure copy cannot resurface later:

```
<fallback-dir>/.tombstones/<hexname of id>.deleted
content: {"v":1,"id":"<UTF-8 ID>"}
```

- The file is only honored if the embedded ID's §2 hash matches its name.
- When the secure store becomes reachable, `list()` and `migrateToSecure()` apply every tombstone (delete there) before merging results.
- A new successful write clears the tombstone.
- Permissions: `.deleted` files are `0600` and `.tombstones/` is `0700` on desktop POSIX (verified after `chmod`).

## 9. In-memory (`MemoryKeystoreBackend`)

No on-disk representation. Holds `SealedRecord` objects in a `Map` keyed by ID. Test-only / ephemeral.

## Versioning and migration

- PQKS version is 1 (ADR-0006 work pending; parser is strict).
- PQNA and PQNW are version 1. There is no cross-platform migration of envelopes: records move between backends only as PQKS (decrypt with the old `PqKeystoreCrypto`, re-encrypt with the new one through `migrateToSecure`-style copy of sealed records *is not* possible across OS envelopes — migrate the plaintext through `PqKeystore` re-wrap or the OS secure store if the platform allows export).
- A `PQNA` file is never parsed as `PQNW` and vice versa: the magic differs and the parser checks it.
