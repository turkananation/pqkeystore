# Claim Boundary

This document explicitly defines what security properties `pqkeystore` claims to provide and what it specifically does not claim.

> **[!WARNING]**
> Always consult this document before assuming security properties. Any new security features must be added here as explicit claims.

## Implemented Behavior (Limited Claims)

* **PQKS framing**: The codec recognizes the `PQKS` magic and supported version and decodes the defined fields. This is format parsing, not a claim that a record or backend index is authenticated against an attacker. The current decoder accepts trailing bytes; see [`BUGS.md`](BUGS.md).
* **Passphrase input policy**: `PqKeystore.put` rejects `PlatformUnlock` for v1 and accepts passphrase-based unlock variants. This describes API policy only; cryptographic strength and exact provider semantics depend on the injected `PqKeystoreCrypto` implementation.
* **Share helper policy**: `putShare` requires `KeyKind.thresholdShare` and non-null threshold metadata, then delegates to generic storage. It does not establish that share parameters are valid or that a threshold ceremony has succeeded.
* **Callback cleanup attempt**: `use` clears the callback copy in a `finally` block and disposes the `SecretBytes` wrapper. The original unwrap buffer ownership and complete memory-erasure behavior have not been verified, so complete zeroization is not claimed.
* **Platform channel contract v1 (client side)**: `PlatformKeystoreBackend` validates IDs, record size, and options before calling native code; refuses to operate on a contract-version mismatch; rejects records whose decoded metadata ID differs from the requested ID; and never silently ignores a storage option (unsupported options fail with `UNSUPPORTED_OPTION`). Evidence: `test/platform_backend_test.dart` against the pure-Dart reference in `test/contract/`. See [`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md).
* **Linux native backend (limited)**: On the evidence of the shared contract suite passing locally against gnome-keyring (Pop!_OS 24.04, Flutter 3.47.5), the Linux plugin stores records in the Secret Service default collection and fails with `UNAVAILABLE`, rather than falling back to files, when no Secret Service is reachable. This is behavioral parity evidence only. The Secret Service has **no per-application isolation**: any process in the same user session can read these items, and at-rest protection depends on the provider (e.g. gnome-keyring, KWallet).
* **Fallback file store (limited, opt-in)**: When a caller chooses `FallbackKeystoreBackend` and the OS secure-storage facility reports `UNAVAILABLE`, sealed records are written as `.pqks` files in a dedicated directory with `0700`/`0600` permissions on desktop POSIX. Their only protection is the crypto provider wrapping inside each record; deletion leaves tombstones so records cannot resurface in the secure store after recovery. This is weaker than OS keychain/keystore protection and is never selected automatically.
* **Metadata confidentiality**: PQKS serializes `KeyMetadata` in cleartext. Do not place secrets or sensitive personal data in metadata unless the selected backend's confidentiality behavior has been explicitly reviewed.

## Planned Invariant, Not Yet Claimed

* **Metadata AAD binding**: `put` computes canonical metadata AAD and supplies it to the crypto adapter. On retrieval, the facade does not currently verify that the stored AAD equals canonical AAD recomputed from stored metadata. Therefore end-to-end metadata tamper detection is not currently claimed. See [`BUGS.md`](BUGS.md) and [ADR-0006](adr/0006-pqks-record-invariants.md).

## Non-Claims (What we DO NOT guarantee)

* **Cryptographic Strength**: `pqkeystore` DOES NOT claim that the underlying encryption is strong. The strength is entirely dependent on the injected `PqKeystoreCrypto` implementation.
* **Platform availability or isolation**: Android, iOS, macOS, and Windows implementations of contract v1 exist in source but have **no passing on-device evidence yet** (CI jobs defined in `.github/workflows/ci.yml`). Until those jobs pass they are not claimed to work. Even then no claim is made of hardware backing (TEE/StrongBox/Secure Enclave), of equivalent protection across platforms, or of isolation from other processes running as the same user. Windows DPAPI user scope and the Linux Secret Service do not isolate applications from each other.
* **Option enforcement beyond the reported capability set**: A capability is enforced only when it appears in `platformInfo.supportedOptions` on that device at write time. On Android, `afterFirstUnlock` relies on credential-encrypted storage, and `whenUnlocked` on `setUnlockedDeviceRequired`; neither is re-checked if the user later removes the lock screen. Behavior of biometric-bound Apple items after biometric re-enrollment is unverified.
* **Physical erasure**: `delete` is logical deletion. No claim is made that bytes are erased from flash, NTFS, or keychain/secret-service databases.
* **Backup and migration**: Platform records are device-bound. Android and Windows protecting keys do not leave the device/user profile, and Android records are excluded from backup. No restore or cross-device migration is offered.
* **File index authenticity**: The current index checksum is unkeyed and is not adversarial tamper authentication.
* **Side-channel resistance**: No resistance to timing, power, or memory-snooping attacks is claimed.
* **Callback confinement**: The callback can copy or retain the plaintext it receives. The API cannot prevent caller leakage or copies outside the buffer it clears.
* **Complete memory erasure**: Dart/runtime copies, provider-owned buffers, and dependency disposal semantics are not fully verified; overwriting one callback buffer is not proof of complete erasure.
* **Threshold validity**: Metadata checks do not validate share mathematics or a DKG/signing ceremony.
* **Format interoperability**: PQKS is not the pqforge `.pqf` or `.pqfs` content-envelope format. No cross-format import/export compatibility is claimed.

## Current State

> **[!CAUTION]**
> `StubKeystoreCrypto` is insecure and provides no production security. A `PqForgeKeystoreCrypto` adapter exists, but its provider behavior and the complete package/platform system have not been independently validated. Do not infer production readiness from adapter presence. See [`TRACKER.md`](TRACKER.md) for release gates.
