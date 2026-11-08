# Continuation Guide

[`doc/TRACKER.md`](doc/TRACKER.md) is the source of truth for production work;
[`doc/BUGS.md`](doc/BUGS.md) lists confirmed defects. Where this file and the
tracker disagree, the tracker wins.

## Latest verification

`tool/verify.sh` is the Dart gate. The approved minimum is Dart 3.12.2 /
Flutter 3.44.2 (oldest stable pair that resolves `pqthreshold` 1.1.0).
Flutter 3.24.0 ships Dart 3.5.0 and cannot resolve the package. The current
local toolchain and the command log are in
[`doc/SDK_BASELINE.md`](doc/SDK_BASELINE.md). CI pins Flutter 3.47.5 for the
native jobs and also runs the minimum pair.

CI run 37770096113 on merged `main`:

| Job | Result |
| --- | --- |
| Dart (verify.sh, incl. example) | pass |
| Linux (libsecret) | pass |
| Windows (DPAPI) | pass |
| Android API 26 / 28 / 35 | pass |
| iOS (SwiftPM) | pass |
| iOS (CocoaPods) | build OK, gated on a signing identity |
| macOS | build OK, gated on a signing identity |

This verifies behaviour, not any production security claim. The minimum pair
is no longer "Dart 3.12.0 / Flutter 3.24.0"; that pair cannot resolve the
package.

## What the platform-contract work delivered

Contract v1 is implemented and merged on all five targets, together with file
store v1 (ADR-0010) and the opt-in `FallbackKeystoreBackend`. Two defects
found during that work were fixed on `main`:

- **PQNA v2** — AndroidKeyStore AES-GCM fails tag verification for payloads
  above ~64–256 KiB on API ≤ 28, so records are now sealed as 48 KiB chunks,
  each with its own IV and AAD. Verified on-device up to the 1 MiB contract
  maximum.
- **Darwin keychain accounts** — the keychain merged canonically equivalent
  UTF-8 IDs (NFC vs NFD `café`), so accounts are now `base64url(UTF-8 ID)` and
  `listIds` compares UTF-8 bytes rather than Swift `String` equality.

## Open work, in the order the gates require

1. **TRK-001 — closed.** Approved minimum is Dart 3.12.2 / Flutter 3.44.2. Record: [`doc/SDK_BASELINE.md`](doc/SDK_BASELINE.md).
2. **TRK-002 — architecture freeze.** ADR-0002 … ADR-0010 are implemented in part and still marked `Proposed` except ADR-0005. A maintainer accepts them as written, or defers them explicitly. This PR does not accept them.
3. **Apple signing identity.** Provision `DEVELOPMENT_TEAM` plus a certificate
   in CI to unblock the macOS and iOS-CocoaPods legs. Both jobs already fail
   fast with an explicit error; no code change is needed.
4. **TRK-005 — closed.** Provider ownership, passphrase encoding, unlock policy, and KDF bounds are recorded in [`doc/PROVIDER_LIFECYCLE.md`](doc/PROVIDER_LIFECYCLE.md). The three non-claims (GC copies, the immutable passphrase `String`, unreachable `pqforge` temporaries) stay non-claims.
5. **TRK-008 — closed.** Share metadata invariants are accepted in ADR-0005 and tested. Ceremony interoperability stays unclaimed until there is an end-to-end `pqthreshold` test.
6. **TRK-010 — closed** as a documentation reconciliation against the code on this branch. Proposed ADRs are still Proposed. Plans under `doc/IMPLEMENTATION/` are not current behaviour.
7. **TRK-011 — closed as a non-publication decision.** `publish_to: none`, no tag. A clean-tree dry-run validates an archive and does not upload; `pod spec lint` was not run. CI built the CocoaPods iOS target and then stopped before the contract suite. See [`doc/PUBLICATION.md`](doc/PUBLICATION.md). TRK-007 and TRK-009 stay open.
8. **TRK-012 — independent security review.** No production-security claim may be made before this closes.

## Hard rules that are easy to break

- [`AGENTS.md` rule 1](AGENTS.md) — never print, log or leak secret material.
- [`AGENTS.md` rule 10](AGENTS.md) — **every** plaintext buffer must be wiped
  with `secureZero`, including the one returned by `unwrap`, because
  `SecretBytes.fromUint8List` copies rather than takes ownership. Every such
  site needs a regression test that *fails when the wipe is removed*.
- [`AGENTS.md` rule 5](AGENTS.md) — update [`CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md)
  **before** making or assuming a security claim. Prefer under-claiming.

## Format reminder

PQKS is the keystore's persisted record. `PqWrappedKey` is pqforge's
passphrase-based key wrapper. `.pqf` and `.pqfs` are pqforge recipient-oriented
one-shot and streaming content envelopes; neither is a pqkeystore backend
record. See
[ADR-0007](doc/adr/0007-pqks-and-pqforge-format-boundaries.md) and
[`FORMATS.md`](doc/FORMATS.md) for every byte layout the package reads or
writes.
