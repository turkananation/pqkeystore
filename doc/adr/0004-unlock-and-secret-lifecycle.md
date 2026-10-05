# ADR-0004: Unlock Semantics And Secret Lifecycle

- Status: Proposed
- Date: 2026-10-04

## Context

The facade rejects `PlatformUnlock` for PQKS v1. `PqForgeKeystoreCrypto` accepts passphrase-based wrapping, but `PassphraseThenPlatform` is currently handled as passphrase-only. `PlatformStoreOptions` are not consistently consumed by native code. In the resolved `zeroize` API, `SecretBytes.fromUint8List` always copies and leaves the caller's buffer owned by the caller; the facade disposes the copy but does not currently clear the original plaintext returned by `unwrap`. Pure Dart also cannot guarantee erasure of garbage-collected copies. The adapter converts passphrase bytes to a Dart `String`, which cannot be explicitly wiped.

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
