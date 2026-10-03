# Agent Guidelines for `pqkeystore`

This file encodes the **HARD RULES** and structural guidelines for any AI agent or developer modifying the `pqkeystore` package.

## 🔴 CRITICAL RULES

1. **NO SECRETS IN LOGS**: Never print, log, or leak secret material, key data, passphrases, or shares in standard output, error streams, or test logs.
2. **PREFERRED API**: Applications MUST be directed to use `PqKeystore.use(id, callback)`. Direct extraction of plaintext keys should be strongly discouraged.
3. **NO MATH**: Do NOT implement lattice or post-quantum cryptographic mathematics here. `pqkeystore` is strictly for **custody, storage, and lifecycle management**. Mathematical operations belong in `pqforge` or `pqcrypto`.
4. **THRESHOLD SUPPORT**: The keystore stores and uses *shares*. Full key reconstruction in a single device's memory is high-friction, must be explicit, and defaults to OFF. Use `putShare` and `useShare`.
5. **CLAIM BOUNDARIES**: Update `doc/CLAIM_BOUNDARY.md` BEFORE making or assuming any new security claim. Prefer under-claiming over over-claiming.
6. **PLATFORM PARITY**: All five target operating systems (Android, iOS, macOS, Windows, Linux) MUST use the exact same MethodChannel name (`com.yardenah.pqkeystore/store`) and the exact same method signatures.
7. **PURE DART TESTABLE**: Core logic MUST be fully testable without a physical device or emulator. This means relying on `MemoryKeystoreBackend`, `FileKeystoreBackend`, and the PQKS codec alongside unit tests.
8. **STUB IS INSECURE**: `StubKeystoreCrypto` is **NOT SECURE**. It is for structure and CI tests only. Never ship it as production crypto, and log warnings if it is instantiated.
9. **NO REAL KEYS**: Never commit `*.pqks` files containing real data, passphrases, or active key material to the repository.

## Package Overview

`pqkeystore` is a custody layer. It takes raw bytes, wraps them in a structured PQKS format (using a crypto provider), and hands that blob to a backend (Memory, File, or OS Platform) for safekeeping.

## Architecture Quick-Ref

* `PqKeystore`: The main facade.
* `PqKeystoreBackend`: Interface for storage (put/get raw bytes).
* `PqKeystoreCrypto`: Interface for wrapping/unwrapping key material into PQKS format.
* `PQKS`: Post-Quantum Key Store format. A sealed, versioned binary blob.

## Naming Conventions

* Classes and types: `PqKeystore`, `PqKeystoreBackend`, `PQKS`.
* Acronyms: PQKS is capitalized when used as an acronym, but PascalCase in class names (`PqksCodec` if implemented as a class).

## Data Directories

* `lib/src/`: Internal implementation details.
* `lib/`: Public exports.
* `test/`: Unit and integration tests.
* `doc/`: Architecture and security documentation.
* `tool/`: Verification and build scripts.
