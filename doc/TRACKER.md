# Production Readiness Tracker

This is a draft production-readiness tracker based on a source audit. Priority levels, sequencing, and release gates are recommendations for review, not approved commitments. Status reflects source inspection only; commands, platform builds, and release workflows have not yet been verified. The requirement for all five registered platforms in v1 is the confirmed project direction.

## Current State

| Area | Current state | Evidence |
| --- | --- | --- |
| Facade and record lifecycle | `PqKeystore` provides put/use/delete/list/metadata and share helpers. Constructor/API consistency needs repair. | [`pq_keystore.dart`](../lib/src/api/pq_keystore.dart) |
| PQKS format | Versioned encoding/decoding and canonical metadata AAD are implemented; strict metadata binding and trailing-byte rejection need work. | [`sealed_record.dart`](../lib/src/api/sealed_record.dart), [`canonical_aad.dart`](../lib/src/crypto/canonical_aad.dart) |
| Crypto adapter | `PqForgeKeystoreCrypto` exists; provider behavior and plaintext buffer lifecycle are not independently verified. Stub crypto is explicitly insecure. | [`pq_forge_keystore_crypto.dart`](../lib/src/crypto/pq_forge_keystore_crypto.dart), [`stub_keystore_crypto.dart`](../lib/src/crypto/stub_keystore_crypto.dart) |
| Dart backends | Memory and file backends exist. File ID mapping, replacement durability, and index threat model need resolution. | [`memory_keystore_backend.dart`](../lib/src/backend/memory_keystore_backend.dart), [`file_keystore_backend.dart`](../lib/src/backend/file_keystore_backend.dart) |
| Native backends | Android and Apple implementations are partial and contract-incompatible with Dart. Linux and Windows are stubs. None is considered production-ready from this audit. | [`platform_keystore_backend.dart`](../lib/src/backend/platform_keystore_backend.dart), platform directories |
| Automated verification | Unit tests and `tool/verify.sh` exist. Their current pass status, native builds, and CI coverage are unverified. | [`test/`](../test/), [`verify.sh`](../tool/verify.sh) |
| Release readiness | Package is `0.1.0-dev.1`, publication is disabled, and native package metadata contains placeholders. | [`pubspec.yaml`](../pubspec.yaml), `ios/pqkeystore.podspec`, `macos/pqkeystore.podspec` |

## Work Items

Status vocabulary: **Open** means not completed or not verified; **Blocked** means a preceding decision or task is required. No item is marked complete based only on documentation or source inspection.

| ID | GitHub issue | Priority | Status | Work and acceptance criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| TRK-001 | [#1](https://github.com/turkananation/pqkeystore/issues/1) | P0 | Open | Establish a reproducible baseline on the declared minimum Flutter/Dart toolchain. `flutter pub get`, `dart analyze`, and `flutter test` pass; example constraints can resolve the package; record toolchain versions and results. | None |
| TRK-002 | [#2](https://github.com/turkananation/pqkeystore/issues/2) | P0 | Open | Align the public constructor, exported API, examples, tests, and API reference. A consumer can construct `PqKeystore` with public named arguments; a package example compiles against the exported barrel API. | TRK-001 |
| TRK-003 | [#3](https://github.com/turkananation/pqkeystore/issues/3) | P0 | Open | Enforce record invariants before unwrap: canonical metadata must match authenticated AAD; reject trailing bytes and malformed or oversized fields; stored metadata identity must agree with the requested ID. Focused tamper and parser tests pass. | [ADR-0006](adr/0006-pqks-record-invariants.md) |
| TRK-004 | [#4](https://github.com/turkananation/pqkeystore/issues/4) | P0 | Open | Make file storage collision-safe and interruption-safe. Distinct valid IDs never alias; failed replacement preserves the previous valid record; index behavior and filesystem permissions match the approved threat model. | [ADR-0003](adr/0003-file-backend-threat-model.md) |
| TRK-005 | [#5](https://github.com/turkananation/pqkeystore/issues/5) | P0 | Open | Verify the `pqforge` adapter's algorithm/KDF parameter handling and establish plaintext ownership, clearing, and disposal semantics. Tests cover successful use and callback failure without logging secret material; claims match what can actually be cleared. | [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md) |
| TRK-006 | [#6](https://github.com/turkananation/pqkeystore/issues/6) | P0 | Open | Define and implement one Dart/native channel contract, including exact argument names/types, `delete` result, `listIds`, error mapping, metadata operations, and option behavior. Contract tests pass against every native implementation. | [ADR-0002](adr/0002-platform-channel-contract.md) |
| TRK-007 | [#7](https://github.com/turkananation/pqkeystore/issues/7) | P0 | Open | Deliver working Android, iOS, macOS, Windows, and Linux storage implementations under the common contract. Each target builds and passes CRUD/list/error contract tests; unsupported options fail explicitly rather than silently degrading. | TRK-006 |
| TRK-008 | [#8](https://github.com/turkananation/pqkeystore/issues/8) | P1 | Open | Specify share validation and the boundary with `pqthreshold`. Tests prove accepted metadata policy and that this package does not reconstruct a full key implicitly. Do not claim ceremony integration until exercised end-to-end. | [ADR-0005](adr/0005-threshold-share-boundary.md) |
| TRK-009 | [#9](https://github.com/turkananation/pqkeystore/issues/9) | P0 | Open | Add repeatable CI for Dart checks and all five platform builds/contracts, with supported toolchain matrix and actionable failure output. No secrets or key material appear in logs. | TRK-001, TRK-006, TRK-007 |
| TRK-010 | [#10](https://github.com/turkananation/pqkeystore/issues/10) | P1 | Open | Reconcile API, platform, integration, security, and roadmap docs with implemented behavior and accepted ADRs. Every security claim has implementation/test evidence or is stated as a non-claim. | TRK-003 through TRK-008 |
| TRK-011 | [#11](https://github.com/turkananation/pqkeystore/issues/11) | P1 | Open | Finalize package release metadata, SDK support policy, example compatibility, changelog, publishing policy, and native podspec metadata. A release candidate can be built from a clean checkout without placeholders. | TRK-001, TRK-007, TRK-009 |
| TRK-012 | [#12](https://github.com/turkananation/pqkeystore/issues/12) | P0 | Open | Complete an independent security review of the final release candidate and close or explicitly accept all findings. Re-review [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md); do not claim production security before this gate. | TRK-003 through TRK-011 |

## Release Gates

1. **Dart core:** TRK-001 through TRK-005 are complete with focused regression tests.
2. **Platform parity:** TRK-006 and TRK-007 are complete for all five registered targets; CI covers the supported build matrix.
3. **Operational readiness:** TRK-008 through TRK-011 are complete, and documentation reflects verified behavior.
4. **Security sign-off:** TRK-012 is complete. Any remaining accepted risk is documented with an owner and rationale.

## Risks And Unknowns

- The `zeroize` package's ownership/copy/disposal semantics and the `pqforge` internals require dependency-level verification.
- The current file index uses an unkeyed checksum; it must not be represented as adversarial tamper authentication absent an approved keyed design.
- Native platform option semantics, hardware backing, and user-presence enforcement are not established by the current implementations.
- Current test and build commands have not been run in this audit. “Exists” does not mean “passes.”
