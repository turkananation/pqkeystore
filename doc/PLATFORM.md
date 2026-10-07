# Platform Support Matrix

All five registered targets are required for v1 ([ADR-0001](adr/0001-five-platform-v1.md)). A platform counts as **supported** only when its CI job builds the plugin and the shared contract suite passes against the real native implementation. Source presence is not support.

- Contract: [`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md) (ADR-0002, Proposed)
- Per-platform design and limits: [ADR-0009](adr/0009-native-backend-designs.md) (Proposed)
- Claims: [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md)
- On-disk formats for every backend: [`FORMATS.md`](FORMATS.md)

## Current Status

| Platform | Mechanism | Source | Evidence | Status |
| :--- | :--- | :--- | :--- | :--- |
| Android | AndroidKeyStore AES-256-GCM, files in `noBackupFilesDir` | Contract v1 | JVM unit tests and emulator suite (API 24/28/35) defined in CI; **not yet run** | Pending CI |
| iOS | Data protection keychain | Contract v1 (shared `darwin/`) | Simulator suite (CocoaPods + SwiftPM) defined in CI; **not yet run** | Pending CI |
| macOS | Data protection keychain | Contract v1 (shared `darwin/`) | Suite defined in CI; needs a signing identity honoring `keychain-access-groups` | Pending CI and signing |
| Windows | DPAPI (user scope) files under `%LOCALAPPDATA%` | Contract v1 | Contract validator unit-tested locally (cross-compiled on Linux); DPAPI store and suite defined in CI; **not yet run** | Pending CI |
| Linux | Secret Service (libsecret), no fallback | Contract v1 | Native unit tests 6/6; contract suite 29/29 against gnome-keyring; no-Secret-Service test passes (local, 2026-10-07) | Local evidence; CI pending |

## Enforceable Options

Reported per device via `PlatformKeystoreBackend.platformInfo().supportedOptions`. Anything not listed is rejected with `UNSUPPORTED_OPTION`. Default options (`PlatformStoreOptions()`) are accepted everywhere.

| Capability | Android | iOS / macOS | Windows | Linux |
| --- | --- | --- | --- | --- |
| `requireUserPresence` | No (v1) | If a passcode/password is set | No | No |
| `requireBiometric` | No (v1) | If biometrics are enrolled | No | No |
| `accessibility.whenUnlocked` | API 28+ with a secure lock screen | Yes | No | No |
| `accessibility.afterFirstUnlock` | FBE + secure lock screen | Yes | No | No |
| `synchronizable` | No | Yes (iCloud Keychain) | No | No |

What `platformDefault` means:

- **Android**: AndroidKeyStore key, no unlock binding; files live in credential-encrypted storage.
- **Apple**: `WhenUnlockedThisDeviceOnly`.
- **Windows**: DPAPI, available whenever the user's session is.
- **Linux**: Governed by the collection's lock state.

## Integration Requirements

- **Android**: `minSdk` 24. No permissions needed. Records are excluded from backup by design.
- **iOS**: Add `NSFaceIDUsageDescription` to `Info.plist` if `requireBiometric` or `requireUserPresence` is used.
- **macOS**: Add a `keychain-access-groups` entitlement, e.g. `$(AppIdentifierPrefix)<bundle id>`, and sign with a team identity. Without it, every operation returns `UNAVAILABLE` (`errSecMissingEntitlement`). The legacy file keychain is never used as a fallback.
- **Windows**: No extra setup. Data is namespaced by executable name.
- **Linux**: Build dependency `libsecret-1-dev` (≥ 0.18). Runtime needs a Secret Service provider (gnome-keyring, KWallet ≥ 5.97, KeePassXC). Headless sessions without one get `UNAVAILABLE`.

## Fallback Storage (opt-in)

When the OS secure-storage facility is not available, `FallbackKeystoreBackend` can persist records into a dedicated directory instead of failing. It is **opt-in** and only activates on `UNAVAILABLE`; `LOCKED`, `USER_CANCELLED`, `AUTH_FAILED`, and option-enforcement errors are surfaced, not bypassed:

```dart
final backend = FallbackKeystoreBackend(
  secure: PlatformKeystoreBackend(),
  fallback: FileKeystoreBackend(Directory('<app-support>/pqkeystore')),
  onFallback: (reason) => log.warning('using file fallback', reason),
);
```

- Reads consult the fallback copy first (it is never older than the secure copy), then secure storage.
- A successful secure write removes the fallback copy; `migrateToSecure()` moves all fallback records to secure storage.
- A `delete` issued while the secure store is unavailable leaves a tombstone so the record cannot resurface when the store recovers.
- Protection of fallback files equals the protection inside the PQKS record (the same `PqKeystoreCrypto`). Treat the directory as private; do not point it at a shared folder.

## Known Limitations

- **L1 (Linux)**: The embedder codec truncates strings at U+0000. Only the Dart client can reject NUL in IDs.
- `list()` reads every record. With access-controlled Apple items this may prompt once per record.
- Windows calls run on the platform thread (bounded: ≤ 1 MiB, no UI).
- Linux: the first operation waits at most 5 s for an unreachable Secret Service before failing.
- No cross-device migration, backup/restore, or physical-erasure guarantees.

## Verifying Locally

```sh
tool/verify.sh                                   # pure Dart, no device
cd example
flutter test integration_test/platform_contract_test.dart -d <device>
```
