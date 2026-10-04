# Roadmap

This roadmap reflects source-audit status, not passing test/build results. The detailed work breakdown and acceptance criteria are in [`TRACKER.md`](TRACKER.md); confirmed defects are in [`BUGS.md`](BUGS.md). All five registered platforms are required for v1 by [ADR-0001](adr/0001-five-platform-v1.md).

## Existing Capabilities

- Dart facade, versioned PQKS record codec, canonical AAD generation, memory/file backends, and a `PqForgeKeystoreCrypto` adapter exist.
- Android has a partial native handler; iOS and macOS have partial Keychain handlers.
- Linux and Windows plugin sources are stubs.
- Tests and a verification script exist, but the audit did not run them. No passing baseline is claimed.

## Production Sequence

1. **Restore a usable and verified Dart baseline** (TRK-001, TRK-002): run the declared verification flow on the minimum supported toolchain and fix the public constructor/API mismatch.
2. **Enforce data and filesystem invariants** (TRK-003, TRK-004): metadata/AAD binding, strict bounded PQKS parsing, collision-safe IDs, safe replacement, and an explicit index threat model.
3. **Verify crypto and secret lifecycle** (TRK-005): establish provider behavior and buffer ownership/cleanup evidence; define unlock semantics in ADR-0004.
4. **Make all platform implementations conform** (TRK-006, TRK-007): approve the channel contract, implement Android/iOS/macOS/Windows/Linux, and run shared contract tests/builds.
5. **Close policy, automation, and release work** (TRK-008 through TRK-012): threshold boundary, CI matrix, accurate docs, package metadata, release candidate, and independent security review.

## Release Policy

Do not call the package production-ready or publish a stable release until all release gates in [`TRACKER.md`](TRACKER.md) have evidence. Update [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md) before asserting any newly implemented security property.
