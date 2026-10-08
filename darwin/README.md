# pqkeystore — iOS & macOS (shared Darwin source)

Single Swift implementation of
[platform channel contract v1](../doc/PLATFORM_CONTRACT.md) for **both**
Apple platforms (`sharedDarwinSource: true` in `pubspec.yaml`; the CocoaPods
spec and the Swift package build the identical sources). Design and limits:
[ADR-0009](../doc/adr/0009-native-backend-designs.md).

> One codebase, one behaviour. There is no iOS-specific or macOS-specific
> storage path, and no platform can drift from the other without changing this
> directory.

## Storage model

| Property | Value |
| --- | --- |
| Item class | `kSecClassGenericPassword` |
| Service | `com.yardenah.pqkeystore.v1` |
| Account | `base64url(UTF-8 ID)` — see *Why the account is encoded* below |
| Value | the raw PQKS record in `kSecValueData` |
| Keychain | **data protection keychain** (`kSecUseDataProtectionKeychain = true`) on macOS too |
| Legacy file keychain | never used |
| Record size | 1 byte … 1 MiB |
| ID size | 1 … 256 UTF-8 bytes, no U+0000 |

Native code stores **one opaque PQKS blob per ID and nothing else**. It never
parses metadata and reserves no ID prefix, so there is no `__meta__` namespace
and no sidecar record to collide with a caller's ID.

### Why the account is encoded

`kSecAttrAccount` is matched by the keychain, and the keychain treats distinct
UTF-8 byte strings with canonically equivalent forms as **one** account. An ID
of `café` composed (NFC) and the same text decomposed (NFD) are different
strings, but they were resolving to a single item — two distinct IDs silently
sharing one stored record.

The account is therefore `base64url(UTF-8 ID)`: an ASCII-safe, injective and
reversible encoding of the exact bytes. Distinct IDs can no longer be merged by
any normalization the keychain performs. `listIds` decodes each account back to
the original ID and compares **UTF-8 bytes**, never `String` equality, because
Swift's `String` `==` is itself canonical-insensitive and would reintroduce
exactly the bug this encoding removes.

## Crash-safe replacement

The keychain has no rename, so replacement is staged:

1. delete any stale staged item,
2. `SecItemAdd` the new value under `…v1.pending`,
3. delete the old item under `…v1`,
4. `SecItemUpdate` the staged item's service to `…v1`.

A crash between steps leaves at most a *pending* item, never a lost record. On
attach, `recoverPending()` reconciles leftovers: if the committed item exists
the staged value is discarded (the `put` never reported success); if it does
not, the staged value is promoted, because it is then the only copy.

## Capabilities

Reported dynamically in `platformInfo.supportedOptions`, evaluated per device:

| Option | Offered when | Enforced by |
| --- | --- | --- |
| `requireUserPresence` | `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)` | `SecAccessControlCreateWithFlags(.userPresence)` |
| `requireBiometric` | `…WithBiometrics` evaluates (passcode + enrolled biometrics) | `SecAccessControlCreateWithFlags(.biometryCurrentSet)` |
| `accessibility.whenUnlocked` | always | `kSecAttrAccessibleWhenUnlocked[ThisDeviceOnly]` |
| `accessibility.afterFirstUnlock` | always | `kSecAttrAccessibleAfterFirstUnlock[ThisDeviceOnly]` |
| `synchronizable` | always | `kSecAttrSynchronizable`, iCloud path on macOS |

The `ThisDeviceOnly` variants are used whenever `synchronizable` is **not**
requested, so a record never silently migrates through iCloud. When
`requireUserPresence` or `requireBiometric` is requested, the item carries
`kSecAttrAccessControl` **instead of** `kSecAttrAccessible` — the keychain
ignores both, and setting the wrong one silently weakens the item.

`.biometryCurrentSet` means adding or removing a fingerprint invalidates the
item on purpose; that behaviour is intentionally *not* claimed as stable across
re-enrollment.

## Threading

All keychain work runs on **one serial queue**, never the main thread — an
authentication prompt presented on the main thread deadlocks the app. Results
are delivered back on the main thread. Calls are therefore FIFO and never
concurrent.

## Signing and entitlements (read this before the first macOS build)

macOS CI and local macOS builds **fail fast** with an explicit "no Apple
development signing identity" error unless one is provisioned. This is
intentional, and it is why the failure is loud instead of a mysterious timeout.

The data protection keychain requires a `keychain-access-groups` entitlement
that only a real signing identity satisfies:

- iOS: add `NSFaceIDUsageDescription` to `Info.plist` if you request
  `requireBiometric`.
- macOS: the app needs a `keychain-access-groups` entitlement and must be
  signed with a Development or Distribution identity. An unsigned or ad-hoc
  build cannot use the data protection keychain and reports `UNAVAILABLE`
  (`errSecMissingEntitlement`).

Without a team-signed build the job is red **by design** rather than silently
green. Provision `DEVELOPMENT_TEAM` (plus certificate) in CI to make the macOS
and iOS-CocoaPods legs run; no code change is required.

## Source map

| File | Role |
| --- | --- |
| `pqkeystore/Sources/pqkeystore/PqKeystorePlugin.swift` | Entire plugin: channel, options, keychain I/O, pending-item recovery |
| `pqkeystore/Sources/pqkeystore/PrivacyInfo.xcprivacy` | Privacy manifest — the plugin collects no data and uses no required-reason API |
| `pqkeystore.podspec` | CocoaPods spec (iOS + macOS) |
| `pqkeystore/Package.swift` | Swift Package Manager manifest (iOS 15 / macOS 12) |

Links `Security` and `LocalAuthentication`.

## Build configuration

- Minimum: iOS 15.0, macOS 12.0.
- CocoaPods and SwiftPM produce the same binary from the same sources.
- The privacy manifest is shipped as a resource bundle in both paths.

## Tests

The shared contract suite runs against the real keychain on a simulator:

```sh
flutter test integration_test/platform_contract_test.dart -d <simulator-udid>
```

CI runs both the SwiftPM and CocoaPods variants
([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)). iOS SwiftPM is
currently green; the CocoaPods job is gated on the signing identity described
above.

## What is NOT claimed

- **Secure Enclave / hardware backing.** Keychain item protection is whatever
  the OS and device provide; the plugin never claims more.
- **App isolation on macOS.** Keychain items are scoped by the app's code
  signature, but anything running as the same user with the same team
  identifier can address the same service and account.
- **Biometric behaviour after re-enrollment.** `.biometryCurrentSet` makes the
  item invalid when biometrics change; that is enforced by the OS, not by us.
- **Post-erasure.** `delete` removes the keychain item; it does not overwrite
  flash or keychain internals.
- **Cross-device or cross-team portability.** Items are tied to the signing
  identity and the access group.
