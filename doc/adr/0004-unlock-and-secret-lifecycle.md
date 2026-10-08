# ADR-0004: Unlock Semantics And Secret Lifecycle

- Status: Proposed
- Date: 2026-10-04

## Context

The facade rejects `PlatformUnlock` for PQKS v1. `PqForgeKeystoreCrypto` accepts passphrase-based wrapping, but `PassphraseThenPlatform` is currently handled as passphrase-only. `PlatformStoreOptions` are not consistently consumed by native code.

In the resolved `zeroize` API, `SecretBytes.fromUint8List` **always copies and never takes ownership**: it states so in its own memory-safety contract. The facade originally disposed the copy but did **not** clear the original plaintext buffer returned by `unwrap`, so key material stayed live in the heap until the garbage collector reclaimed it — readable from swap, core dumps and post-mortem debugging. Pure Dart still cannot guarantee erasure of garbage-collected copies. The adapter converts passphrase bytes to a Dart `String`, which cannot be explicitly wiped.

## Update 2026-10-08

The unwrap-output gap is closed. `PqKeystore.use()` now takes ownership of the buffer returned by `PqKeystoreCrypto.unwrap`, copies it into a `SecretBytes`, and wipes the source with `secureZero` immediately afterwards — inside a `finally`, so the source is cleared even if the copy throws. The callback copy is wiped with `secureZero` rather than a hand-written loop, because `secureZero` is `@pragma('vm:never-inline')` with opaque read anchors and therefore survives Dead Store Elimination in AOT builds. This is now a cardinal project rule: [AGENTS.md rule 10](../../AGENTS.md). `test/secret_lifetime_test.dart` captures the exact buffer instance handed to the facade and asserts it is zeroed on the success path, the throwing-callback path, and the validation-rejection path (where no buffer is produced at all).

Still not solved, and still not claimed: GC-moved copies of a buffer, the immutable `String` holding the passphrase inside the adapter, and OS-level page remanence. Rule 10 deliberately does not widen into those guarantees.

## Decision

Define the meaning of every public unlock type and platform option before advertising platform authentication. Specify passphrase byte-to-text encoding, KDF algorithm and cost policy, FIPS/deployment behavior, and what happens when platform authentication is unavailable. Verify crypto-provider and `zeroize` ownership/copy/disposal behavior against the pinned dependency source and tests. Clear every package-owned source buffer when ownership permits; document only cleanup guarantees that can be demonstrated. Do not promise complete process-memory erasure or OS hardware backing.

## Consequences

- Either implement each advertised unlock flow end-to-end or reject it explicitly with a stable policy error.
- Test successful use, callback exceptions, unwrap failures, and every package-owned buffer cleanup path without logging secret bytes.
- Pin and enforce safe KDF parameter ranges before invoking a password KDF on untrusted record data.
- Update claim-boundary and integration docs after behavior is verified.

## Alternatives Considered

- Treat `PassphraseThenPlatform` as equivalent to passphrase-only. Rejected as ambiguous and misleading to callers.
- Claim all buffers are zeroized because one callback copy is cleared. Rejected until ownership of all aliases is known.
- Assume platform storage options imply biometric/user-presence enforcement. Rejected absent native enforcement and tests.

## Open Questions

- Is platform authentication an outer storage access-control policy, an inner unwrap factor, or both?
- What exact memory-erasure guarantee can be made when `SecretBytes` copies and Dart creates immutable strings?
- What passphrase byte encoding is canonical and compatible with `pqforge`'s `String` API?
- Which KDFs, cost ranges, and deployment/FIPS modes are supported by v1?
- Does platform storage add an independent encryption layer, a user-presence gate, both, or neither on each OS?
