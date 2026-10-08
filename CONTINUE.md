# Continuation Guide

[`doc/TRACKER.md`](doc/TRACKER.md) is the source of truth for production work;
[`doc/BUGS.md`](doc/BUGS.md) lists confirmed defects. Where this file and the
tracker disagree, the tracker wins.

## Latest verification

`tool/verify.sh` passes on Dart 3.13.4 / Flutter 3.47.5 — root and example
dependency resolution, `dart analyze`, and **135** package tests.

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

This verifies behaviour, not the declared minimum SDK pair (Dart 3.12.0 /
Flutter 3.24.0 has never been executed here) and not any production security
claim.

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

1. **TRK-001 — minimum SDK baseline.** Run the declared floor
   (Dart 3.12.0 / Flutter 3.24.0) once in CI and record the result, so the
   floor is confirmed rather than asserted.
2. **TRK-002 — architecture freeze.** ADR-0002 … ADR-0010 are implemented and
   tested but still marked `Proposed`. A maintainer accepts them as written, or
   defers them explicitly. Nothing else can be called final until this
   happens.
3. **Apple signing identity.** Provision `DEVELOPMENT_TEAM` plus a certificate
   in CI to unblock the macOS and iOS-CocoaPods legs. Both jobs already fail
   fast with an explicit error; no code change is needed.
4. **TRK-005 — provider lifecycle evidence.** Record the pinned
   `pqforge`/`zeroize` buffer ownership: which buffers are copied, owned,
   disposed and safe to overwrite. The three remaining non-claims (GC copies,
   the immutable passphrase `String`, `pqforge` internals) are documented in
   [`CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) and stay non-claims until this
   exists.
5. **TRK-008 — threshold boundary.** Tighten share metadata invariants
   (`t`/`n` bounds) and keep ceremony interoperability unclaimed until there is
   an end-to-end `pqthreshold` test.
6. **TRK-011 / TRK-012 — release and review.** Publication policy, version
   scheme, archive inspection, then an independent security review. No
   production-security claim may be made before TRK-012 closes.

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
