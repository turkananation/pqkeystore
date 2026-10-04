# ADR-0004: Unlock Semantics And Secret Lifecycle

- Status: Proposed
- Date: 2026-10-04

## Context

The facade rejects `PlatformUnlock` for PQKS v1. `PqForgeKeystoreCrypto` accepts passphrase-based wrapping, but `PassphraseThenPlatform` is currently handled as passphrase-only. `PlatformStoreOptions` are not consistently consumed by native code. The facade clears a callback copy and disposes `SecretBytes`, but the plaintext buffer returned by `unwrap` and dependency ownership semantics require verification.

## Decision

Define the meaning of every public unlock type and platform option before advertising platform authentication. Verify crypto-provider and `zeroize` ownership/copy/disposal behavior against dependency source and tests. Document only cleanup guarantees that can be demonstrated; do not promise complete process-memory erasure or OS hardware backing without evidence.

## Consequences

- Either implement each advertised unlock flow end-to-end or reject it explicitly with a stable policy error.
- Test successful use, callback exceptions, unwrap failures, and disposal paths without logging secret bytes.
- Update claim-boundary and integration docs after behavior is verified.

## Alternatives Considered

- Treat `PassphraseThenPlatform` as equivalent to passphrase-only. Rejected as ambiguous and misleading to callers.
- Claim all buffers are zeroized because one callback copy is cleared. Rejected until ownership of all aliases is known.
- Assume platform storage options imply biometric/user-presence enforcement. Rejected absent native enforcement and tests.

## Open Questions

- Is platform authentication an outer storage access-control policy, an inner unwrap factor, or both?
- What exact memory-erasure guarantee does `SecretBytes` provide, and can the original unwrap buffer be cleared safely?
- Which algorithms and KDF parameter ranges are supported by the provider adapter?
