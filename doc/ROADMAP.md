# Roadmap

This roadmap reflects the source audit plus the local verification result recorded in [`TRACKER.md`](TRACKER.md); it is not a release qualification. Confirmed defects are in [`BUGS.md`](BUGS.md). All five registered platforms are required for v1 by [ADR-0001](adr/0001-five-platform-v1.md).

## Existing Capabilities

- Dart facade, versioned PQKS record codec, canonical AAD generation, memory/file backends, and a `PqForgeKeystoreCrypto` adapter exist.
- All five natives implement platform channel contract v1 (ADR-0002/0009, Proposed). Linux passes the contract suite locally; the other four await CI evidence.
- On Dart 3.13.4 / Flutter 3.47.5, `tool/verify.sh` passes root/example resolution, analysis, and all 25 tests. Minimum SDK and native builds remain unverified.
- The example app is simulated and does not import the package; the public constructor is not a confirmed blocker.

## Production Sequence

1. **Complete the baseline** (TRK-001): current checks pass on the available toolchain; validate the approved minimum combination and reconcile package/example SDK constraints.
2. **Freeze architecture before implementation** (TRK-002): accept or explicitly defer ADR-0002 through ADR-0008, including the PQKS/PQWrappedKey/PQF/PQFS boundary, metadata/ID/lifecycle policy, platform contract, file threat model, and secret/unlock semantics.
3. **Implement core and consumer gates** (TRK-003 through TRK-005 and TRK-013): strict PQKS/AAD/KDF invariants, file safety/recovery, verified provider lifecycle, and a real compiling example.
4. **Complete platform parity and repeatability** (TRK-006, TRK-007, TRK-009): common channel contract, five native backends, shared tests, and CI.
5. **Close policy and release gates** (TRK-008, TRK-010 through TRK-012): threshold boundary, evidence-aligned docs, package metadata, release candidate, and independent security review.

## Release Policy

Do not call the package production-ready or publish a stable release until all release gates in [`TRACKER.md`](TRACKER.md) have evidence. Update [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md) before asserting any newly implemented security property.
