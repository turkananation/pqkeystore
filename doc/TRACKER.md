# Production Readiness Tracker

This is a draft production-readiness tracker based on a fresh source audit and local verification. Priority levels, sequencing, and release gates are recommendations for review, not approved commitments. All five registered platforms are required for v1. Before implementation resumes, the architecture decisions in TRK-002 must be reviewed and accepted or explicitly marked out of scope.

Latest local verification (2026-10-05): `tool/verify.sh` passed on Dart 3.13.4 / Flutter 3.47.5, including root and example dependency resolution, `dart analyze`, and all 25 tests. The minimum supported SDK combination has not been tested; this is not a release or platform-build qualification.

## Current State

| Area | Current state | Evidence |
| --- | --- | --- |
| Facade and record lifecycle | Public `PqKeystore(backend:, crypto:)` construction compiles and passes tests. The example app is still simulated and does not import the package. | [`pq_keystore.dart`](../lib/src/api/pq_keystore.dart), [`main.dart`](../example/lib/main.dart) |
| PQKS format | Versioned encoding/decoding and canonical AAD generation exist; metadata/AAD enforcement, strict parsing, KDF bounds, provider payload schema, and migration policy remain open. | [`sealed_record.dart`](../lib/src/api/sealed_record.dart), [`canonical_aad.dart`](../lib/src/crypto/canonical_aad.dart) |
| Crypto adapter | `PqForgeKeystoreCrypto` adapts pqforge 0.4.6 `PqWrappedKey` fields into PQKS; it does not serialize `.pqf`/`.pqfs`. The returned unwrap buffer is copied into `SecretBytes` but the source is not cleared. | [`pq_forge_keystore_crypto.dart`](../lib/src/crypto/pq_forge_keystore_crypto.dart), [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md), [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md) |
| Dart backends | Memory and file backends exist. File ID mapping collides, index paths are trusted, replacement is destructive before commit, and concurrency/recovery semantics are unspecified. | [`memory_keystore_backend.dart`](../lib/src/backend/memory_keystore_backend.dart), [`file_keystore_backend.dart`](../lib/src/backend/file_keystore_backend.dart) |
| Native backends | Android and Apple implementations are partial and contract-incompatible with Dart. Linux and Windows are stubs. None is considered production-ready from this audit. | [`platform_keystore_backend.dart`](../lib/src/backend/platform_keystore_backend.dart), platform directories |
| Automated verification | `tool/verify.sh` passed locally on Dart 3.13.4 / Flutter 3.47.5 (25 tests). Minimum SDK, native builds, and CI coverage remain unverified. | [`test/`](../test/), [`verify.sh`](../tool/verify.sh) |
| Release readiness | Package is `0.1.0-dev.1`, publication is disabled, and native package metadata contains placeholders. | [`pubspec.yaml`](../pubspec.yaml), `ios/pqkeystore.podspec`, `macos/pqkeystore.podspec` |

## Work Items

Status vocabulary: **Open** means not completed or not verified; **Blocked** means a preceding decision or task is required. No item is marked complete based only on documentation or source inspection.

| ID | GitHub issue | Priority | Status | Work and acceptance criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| TRK-001 | [#1](https://github.com/turkananation/pqkeystore/issues/1) | P0 | Open | Establish a reproducible baseline on the actual supported minimum Flutter/Dart combination. Current available-toolchain evidence is green (Dart 3.13.4 / Flutter 3.47.5); validate root/example resolution, analyze, and tests at the approved minimum and record exact versions. Reconcile the example's Dart `^3.3.0` constraint with the package's `>=3.12.0` requirement. | None |
| TRK-002 | [#2](https://github.com/turkananation/pqkeystore/issues/2) | P0 | Open | Complete an architecture decision freeze before implementation. Accept or explicitly defer ADR-0002 through ADR-0008; decide native operation/atomicity contracts, file threat model and recovery, unlock/KDF/memory semantics, threshold boundary, strict PQKS schema/migration, PQKS vs pqforge formats, and ID/metadata/lifecycle policy. Update tracker dependencies so no implementation work starts while a required decision is Proposed. | TRK-001 |
| TRK-003 | [#3](https://github.com/turkananation/pqkeystore/issues/3) | P0 | Open | Enforce record invariants before unwrap: canonical metadata must match authenticated AAD; bind record ID to requested ID; reject trailing bytes, malformed/oversized fields, unsupported schemas, and unsafe KDF parameters before expensive work. Focused tamper/parser/resource-bound tests pass. | TRK-002, [ADR-0006](adr/0006-pqks-record-invariants.md), [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md) |
| TRK-004 | [#4](https://github.com/turkananation/pqkeystore/issues/4) | P0 | Open | Make file storage collision-safe and recoverable. IDs never alias; untrusted index paths cannot escape the configured root; failed record/index updates preserve or recover the previous consistent state; concurrency and permissions match the accepted threat model. | TRK-002, [ADR-0003](adr/0003-file-backend-threat-model.md), [ADR-0008](adr/0008-metadata-identity-and-key-lifecycle.md) |
| TRK-005 | [#5](https://github.com/turkananation/pqkeystore/issues/5) | P0 | Open | Verify the pinned `pqforge` adapter contract and KDF policy; define passphrase byte encoding and supported unlock modes; clear package-owned input/output copies where possible; test callback success/failure and ensure claims reflect immutable-string/runtime-copy limits. Never log key material, and make `StubKeystoreCrypto` use unmistakably test-only. | TRK-002, [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md), [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md) |
| TRK-006 | [#6](https://github.com/turkananation/pqkeystore/issues/6) | P0 | Open | Define and implement one Dart/native channel contract: exact method schemas, `delete`/`listIds`/error behavior, reserved ID policy, options, and consistency/atomicity for record plus metadata writes. Contract tests pass against all native implementations. | TRK-002, [ADR-0002](adr/0002-platform-channel-contract.md), [ADR-0008](adr/0008-metadata-identity-and-key-lifecycle.md) |
| TRK-007 | [#7](https://github.com/turkananation/pqkeystore/issues/7) | P0 | Open | Deliver working Android, iOS, macOS, Windows, and Linux storage implementations under the accepted contract and security policy. Each target builds and passes CRUD/list/error/option and persistence tests; unsupported options fail explicitly. | TRK-002, TRK-006 |
| TRK-008 | [#8](https://github.com/turkananation/pqkeystore/issues/8) | P1 | Open | Specify share metadata invariants and the `pqthreshold` responsibility boundary. Test validation and prove no implicit full-key reconstruction; claim ceremony interoperability only after an end-to-end test. | TRK-002, [ADR-0005](adr/0005-threshold-share-boundary.md) |
| TRK-009 | [#9](https://github.com/turkananation/pqkeystore/issues/9) | P0 | Open | Add repeatable CI for Dart checks and all five platform builds/contracts at the supported toolchain matrix. Missing platform jobs must fail/report visibly; logs and artifacts must contain no secrets. | TRK-001, TRK-006, TRK-007 |
| TRK-010 | [#10](https://github.com/turkananation/pqkeystore/issues/10) | P1 | Open | Reconcile all package docs, including `CONTINUE.md`, with verified code and accepted ADRs. Every public/security claim has evidence or is explicitly limited; the format distinction and v1 non-goals are clear. | TRK-002 through TRK-008, TRK-013 |
| TRK-011 | [#11](https://github.com/turkananation/pqkeystore/issues/11) | P1 | Open | Finalize release SDK matrix, example compatibility, version/publishing policy, changelog, native metadata, backup/migration statements, and release archive. A clean checkout passes approved release preflight without placeholders or secret material. | TRK-001, TRK-007, TRK-009 |
| TRK-012 | [#12](https://github.com/turkananation/pqkeystore/issues/12) | P0 | Open | Complete an independent security review of the final release candidate and close or explicitly accept all findings. Re-review [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md); do not claim production security before this gate. | TRK-003 through TRK-011, TRK-013 |
| TRK-013 | [#23](https://github.com/turkananation/pqkeystore/issues/23) | P1 | Open | Replace the simulated example with a real package consumer that imports the public barrel, constructs the facade, and demonstrates a safe `use` callback. It must use test-only material and never present `StubKeystoreCrypto` as production crypto. | TRK-001, TRK-002 |

## Release Gates

1. **Baseline:** TRK-001 records exact passing checks and the approved supported minimum.
2. **Architecture freeze:** TRK-002 is accepted; ADR-0002 through ADR-0008 are Accepted or explicitly scoped out for v1. No implementation issue is started before this gate.
3. **Core and example:** TRK-003 through TRK-005 and TRK-013 pass focused regressions and package/example checks.
4. **Platform and operations:** TRK-006 through TRK-011 pass contract, CI, packaging, documentation, and all-five-platform gates.
5. **Security sign-off:** TRK-012 is complete; residual risks have a maintainer-approved disposition.

## Risks And Unknowns

- The `zeroize` package's ownership/copy/disposal semantics and the `pqforge` internals require dependency-level verification.
- The current file index uses an unkeyed checksum; it must not be represented as adversarial tamper authentication absent an approved keyed design.
- Native platform option semantics, hardware backing, and user-presence enforcement are not established by the current implementations.
- The exact PQKS-to-`PqWrappedKey` mapping and migration policy are unsettled; `.pqf` and `.pqfs` are separate content-envelope formats, not current keystore records.
- Metadata is persisted in cleartext; sensitivity policy, backup/restore, re-wrap, rotation, overwrite, and logical-delete semantics remain open.
- The latest local verification passes on Dart 3.13.4 / Flutter 3.47.5; the declared minimum SDK combination and all native builds remain unverified.
