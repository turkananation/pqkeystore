# ADR-0009: Native Backend Designs (Contract v1)

- Status: Proposed
- Date: 2026-10-07
- Depends on: ADR-0001, ADR-0002, ADR-0003, ADR-0008

## Context

ADR-0001 requires all five targets to implement one storage contract. ADR-0002 proposes that contract, specified in [`PLATFORM_CONTRACT.md`](../PLATFORM_CONTRACT.md). Each OS provides a different secure-storage primitive with different identity, atomicity, isolation, and failure semantics. This ADR records the per-platform choices so their limits are explicit and reviewable.

## Decision

### Common rules

- Native code stores one opaque PQKS blob per ID. No separate metadata, no reserved ID prefixes.
- IDs are mapped injectively and never interpreted as paths. File-based backends use `hex(SHA-256(UTF-8 ID)).pqna` (Android) / `.pqnw` (Windows) and store the ID in an authenticated header, so case-insensitive filesystems, path characters, and reserved device names (`CON`, `NUL`) cannot alias or escape.
- Replacement preserves the previous entry until the new one is committed.
- Optional security capabilities are reported dynamically and either enforced or rejected with `UNSUPPORTED_OPTION`.
- Data is namespaced per application. **Namespacing is not isolation** where the OS does not isolate (Linux, Windows).

### Android — AndroidKeyStore AES-256-GCM + files in `noBackupFilesDir`

- One non-exportable AES-256-GCM key per profile: `com.yardenah.pqkeystore.v1.default`, and `…v1.unlocked` (`setUnlockedDeviceRequired`, API 28+).
- One file per entry in `noBackupFilesDir/pqkeystore/v1/`: `"PQNA" | ver(=2) | profile | idLen | id | nChunks | ivs || chunk_1 || … || chunk_n`, where each chunk is independently sealed with AES-256-GCM using AAD `header || u8 chunk_index`. Chunks exist because API ≤28 AndroidKeyStore GCM can fail tag verification on payloads > ~64 KiB. See [FORMATS.md](../../FORMATS.md) §3.
- Write: temp file → `fsync` → `rename(2)` → directory `fsync`.
- `noBackupFilesDir` is excluded from Auto Backup and device-to-device transfer. The keystore key never leaves the device, so a restored blob would be undecryptable; excluding it avoids "restored but unreadable" states.
- Capabilities: `accessibility.whenUnlocked` (API 28+ with a secure lock screen); `accessibility.afterFirstUnlock` (file-based encryption plus a secure lock screen, enforced by credential-encrypted storage). `requireUserPresence`/`requireBiometric` need `BiometricPrompt` from a `FragmentActivity` and are **not offered in v1**. `synchronizable` has no equivalent.
- Error mapping: `KeyPermanentlyInvalidatedException` or a missing key → `KEY_INVALIDATED`; `UserNotAuthenticatedException` → `LOCKED`; `AEADBadTagException` → `CORRUPT`; storage before first unlock → `LOCKED`.
- A key is never created on the read path.

### iOS and macOS — data protection keychain (shared `darwin/` source)

- Generic-password items: `service = com.yardenah.pqkeystore.v1`, `account = ID`. `kSecUseDataProtectionKeychain = true` on macOS too; the legacy file keychain is never used.
- Accessibility: `WhenUnlocked[ThisDeviceOnly]` (default) or `AfterFirstUnlock[ThisDeviceOnly]`. The non-`ThisDeviceOnly` classes are used only when `synchronizable` is requested.
- `requireUserPresence` → `SecAccessControl(.userPresence)`; `requireBiometric` → `.biometryCurrentSet` (stricter; wins if both are set). Reported only when `LAContext.canEvaluatePolicy` succeeds.
- Crash-safe replacement (`SecItemUpdate` cannot change access control): add under the `…v1.pending` service → delete the old item → rename the pending item's service. At startup, a pending item is discarded if the committed item exists (the put never returned success); otherwise it is promoted (it is the only copy).
- `contains`/`listIds` use an `LAContext` with `interactionNotAllowed`, so they never prompt.
- macOS requires a `keychain-access-groups` entitlement that the signing identity honors. Otherwise the result is `errSecMissingEntitlement` → `UNAVAILABLE`. There is no fallback to the legacy keychain.
- Privacy manifest declares no collection and no required-reason APIs. Both CocoaPods and Swift Package Manager are supported.

### Windows — DPAPI (user scope) protected files

- `%LOCALAPPDATA%\yardenah\pqkeystore\<exe-stem>\v1\` with `\\?\` long paths. Directories created by the plugin get a protected DACL: current user + SYSTEM.
- File: `"PQNW" | ver | idLen | id | blobLen | CryptProtectData(record, entropy = context‖app‖ID, CRYPTPROTECT_UI_FORBIDDEN)`. The entropy binds each blob to its app namespace and ID, and the format is strict (no trailing bytes).
- Write: unique temp file → `FlushFileBuffers` → `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`, retrying transient sharing violations (antivirus). Stale temp files older than 10 minutes are removed at first use.
- Readers open with `FILE_SHARE_DELETE` so replacement is never blocked by our own reads.
- No optional capabilities in v1. Windows Hello (`KeyCredentialManager`) is a candidate for a future `requireUserPresence`.
- Calls run synchronously on the platform thread. They are bounded: at most 1 MiB, and DPAPI never shows UI.

### Linux — Secret Service via libsecret, no fallback

- Schema `com.yardenah.pqkeystore.v1`, attributes `{app, id}`. The secret is canonical base64 (text/plain), because some providers mishandle binary content types. The label is generic and never contains the ID.
- `put` = `secret_service_store_sync` into the default collection (replace semantics; one D-Bus call).
- `contains` matches attributes without unlocking. `listIds`/`get` may prompt to unlock the collection; a still-locked result → `LOCKED`.
- A bounded (5 s) `org.freedesktop.DBus.Peer.Ping` precedes the first connection. A provider that is activatable but broken yields `UNAVAILABLE` instead of hanging.
- **No file fallback.** With no Secret Service, every operation fails with `UNAVAILABLE`; callers may choose `FileKeystoreBackend` explicitly.
- Calls run on one exclusive worker thread; responses are posted to the GTK main context.
- Build dependency: `libsecret-1-dev` (≥ 0.18).

## Consequences

- All five targets implement the same observable contract; differences are visible only through `platformInfo.supportedOptions`.
- Records do not migrate between backends or devices; there is no backup/restore in v1 (ADR-0008).
- Logical deletion only: no claim of physical erasure on flash, NTFS, or keychain databases.
- Linux and Windows provide user-account-level protection only. Any process running as the same user can read the entries.
- `list()` reads each record, so with access-controlled Apple items it may prompt once per record.

## Alternatives Considered

- **Linux file fallback** (`XDG_DATA_HOME`, mode 0600). Rejected: it silently downgrades protection. Callers can opt into `FileKeystoreBackend`.
- **Android SharedPreferences** (previous implementation). Rejected: not durable with `apply()`, auto-backed-up into an undecryptable state, and one XML file for all entries.
- **Android `EncryptedSharedPreferences` / `security-crypto`.** Rejected: the dependency is deprecated/alpha, and it adds nothing over direct AndroidKeyStore use.
- **Legacy macOS file keychain.** Rejected: different access semantics, no `ThisDeviceOnly` classes.
- **Sanitized or encoded IDs as filenames.** Rejected: base64 aliases on case-insensitive filesystems, and hex of a 256-byte ID exceeds filename limits.
- **Separate metadata calls (`putJson`).** Rejected: two non-atomic writes and a reserved ID namespace (BUG-010).

## Open Questions

- Should Android v1 add user presence via `BiometricPrompt` (needs `ActivityAware` and an `androidx.biometric` dependency)?
- Should Windows add Windows Hello–gated keys?
- What exactly happens to `.biometryCurrentSet` items after re-enrollment (`errSecItemNotFound` vs `errSecAuthFailed`)? This needs on-device evidence before mapping it to `KEY_INVALIDATED`.
- Should `list()` gain a non-prompting metadata path (e.g. a native-side cleartext metadata attribute), trading confidentiality for usability?
- macOS CI signing identity for the data protection keychain.
