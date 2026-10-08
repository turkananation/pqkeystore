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
8. **NO INSECURE CRYPTO IN `lib/`**: `lib/` MUST contain exactly one `PqKeystoreCrypto` implementation: `PqForgeKeystoreCrypto`. No XOR stub, no "dev" adapter, no weak-cipher escape hatch, no `debug`-flagged path — none of it, in any build mode. A fixture that does not need real crypto belongs in `test/`, where it cannot ship. `StubKeystoreCrypto` is **removed in 0.2.0** along with every reference to it; see [`doc/IMPLEMENTATION/CROSS-CUTTING.md`](doc/IMPLEMENTATION/CROSS-CUTTING.md) Part A. The adapter's presence is **not** a claim of production readiness — see rule 5 and [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md).
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

11. **FULL IDIOMATIC MODERN DART**: The floor is Dart 3.12. All new and modified code uses the current feature set, and an older idiom is not accepted merely because it also compiles:

    - `sealed` + exhaustively pattern-matched `switch` for closed hierarchies (`UnlockMethod`, `KeyKind`, `UnlockKind`); `abstract interface class` where a third party may legitimately implement it.
    - **Records with named fields** for multi-value returns — `({Uint8List ciphertext, Uint8List nonce, …})`, never positional tuples. The destructuring site is where readers work, and named fields are self-documenting there and at the boundary.
    - `final class` for anything not intended to be extended or implemented. It is what makes a `sealed` hierarchy genuinely closed and it is already the house style.
    - `const` constructors on every immutable value type, and `const` defaults throughout the public API so callers build them at compile time.
    - Enhanced enums with members; `switch` over enum values with **no `default:`**, so a new member becomes a compile error at every unhandled site.
    - Extension types for zero-cost single-representation wrappers (`KeyId`).
    - Collection `if`/`for` elements and spread instead of imperative `add` loops in literals.
    - No `new` keyword. `Uint8List` wherever bytes are meant, never `List<int>`. `package:path` for filesystem paths, never string concatenation. `final` for every local that is never reassigned.
    - Dartdoc on **every** public member stating purpose, guarantees, side effects, and — for anything that touches key material or I/O — thread safety and error behaviour. Non-obvious invariants get a body comment too.

    "Use the newest feature available" is **not** the goal; "do not reach for an older, less safe idiom when the current one is available and clearer" is. Do not introduce extension types over multi-field shapes, `sealed` in the public API purely for ergonomics where the set is genuinely open, or macro-generated code, without evidence they are the right call.

12. **ISOLATE HEAVY CRYPTOGRAPHY, AND BE HONEST ABOUT WHAT IT BUYS**: `pqforge` is **pure Dart** — no `dart:ffi`, and its lattice work is scalar arithmetic in `pqcrypto`. So Argon2id runs on the *caller's* isolate. At this package's defaults (`iterations: 2`, `memoryPowerOf2: 16`, `lanes: 4`) that is a **64 MiB** allocation and a multi-hundred-millisecond block per passphrase `put`, `use`, `rewrap` and `rotate`. Any of those MUST be dispatched off the caller's isolate.

    - Use `Isolate.run` with a **top-level or static** function. A closure capturing non-sendable state does not send.
    - **Secrets cross an isolate boundary as plain `Uint8List`, never as `SecretBytes`.** `package:zeroize` has no isolate support at all — no `SendPort`, `Isolate` or `Transferable` reference anywhere in it — so a `SecretBytes` is at best not sendable and at worst arrives with its wipe discipline intact but its identity broken. Use `TransferableTypedData` for the ciphertext (large, not secret) and a plain wipeable copy for the plaintext.
    - **Wipe on both sides.** The worker's copy in the worker's `finally`; the caller's copy in the caller's `finally`. Rule 10 applies across the boundary, not around it.
    - Do **not** add an isolate to `PlatformKeystoreBackend` paths. Their work is already native and off-thread; a hop adds latency and buys nothing.
    - **Isolates do not reduce peak memory.** The worker allocates its own 64 MiB. An isolate buys back the UI isolate's time; it does not make a large KDF affordable on a memory-constrained device. Never document or imply otherwise — it is also an explicit non-claim in [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md).
    - The decision itself lives in one tested predicate (`lib/src/internal/isolate_policy.dart`, `requiresIsolate`), not in per-call-site judgement.

13. **VALIDATE ATTACKER-CONTROLLED CRYPTO PARAMETERS BEFORE USE**: `kdfParams` comes out of a stored record and is therefore attacker-controlled by anyone who can write one file into the store directory. Range-check every KDF parameter **before** the KDF runs — Argon2id `iterations ∈ [1, 10]`, `memoryPowerOf2 ∈ [10, 20]` (64 MiB – 1 GiB), `lanes ∈ [1, 16]`, `salt.length ≥ 16`. A record claiming `memoryPowerOf2: 30` otherwise requests 1 GiB before authentication is even attempted. Out of range ⇒ `FormatError` naming the parameter and both the observed and permitted range — **never** `CryptoError`, because this is a malformed record, not a failed decryption. The bounds are documented in [`doc/FORMATS.md`](doc/FORMATS.md).

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
