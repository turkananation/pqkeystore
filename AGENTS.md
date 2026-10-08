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
10. **ZERO EVERY PLAINTEXT BUFFER (CARDINAL)**: Any `Uint8List` holding plaintext key material, a share, a passphrase, or any unwrap output **must** be wiped with `secureZero()` from `package:zeroize` before the scope that owns it ends — success path, error path, and exception path alike.

    This rule exists because the obvious pattern is *wrong*. `SecretBytes.fromUint8List(buffer)` **always copies and never takes ownership** (see `zeroize`'s own "Memory-Safety Contract"). Copying a secret into a `SecretBytes` and disposing it does **not** wipe the source buffer; the source stays live in the heap until the garbage collector reclaims it, where swap, core dumps and post-mortem debugging can still read it.

    Required shape:

    ```dart
    final SecretBytes owned;
    try {
      owned = SecretBytes.fromUint8List(plaintext); // copy
    } finally {
      secureZero(plaintext);                        // source wiped, even if the copy throws
    }
    // ... use `owned` ...
    finally { secureZero(callbackCopy); owned.dispose(); }
    ```

    - Use `secureZero(...)`, **not** `fillRange(0, n, 0)`, **not** `buffer[i] = 0`, and **not** `Uint8List.sublist(...)`: `secureZero` is `@pragma('vm:never-inline')` with opaque read anchors, so it survives Dead Store Elimination in AOT builds. A hand-written loop does not.
    - Wipe the original buffer **immediately** after the copy exists, not at the end of the function. Do not keep a second live copy alive "just in case".
    - Prefer constructing `SecretBytes` from a buffer you can immediately wipe, so no unbound secret exists in the first place.
    - Every new plaintext-handling site must ship a regression test that fails when the wipe is removed. `test/secret_lifetime_test.dart` holds the canonical pattern: it captures the exact buffer instance handed to the facade and asserts it is all-zero afterwards. Verify such a test by temporarily reverting the fix and confirming it fails — a test that passes on the buggy code is worthless.
    - Never widen the scope of rule 10 into a false guarantee. Pure Dart cannot prevent the GC from copying a buffer, cannot wipe an immutable `String` (the passphrase conversion in `PqForgeKeystoreCrypto`), and cannot `mlock` pages. Those remain explicit non-claims in [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md); do not silently upgrade them.

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
