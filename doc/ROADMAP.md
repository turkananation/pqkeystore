# Roadmap

Ten releases from `0.1.0` to `1.0.0`. `0.1.0` is the **current, unpublished
first release** — everything that exists on `main` today belongs to it. Every
later version brings one theme of genuinely-new work that is not yet done.

Confirmed defects are in [`BUGS.md`](BUGS.md). Work items and release gates are
in [`TRACKER.md`](TRACKER.md). All five registered platforms are required for
v1.0.0 by [ADR-0001](adr/0001-five-platform-v1.md).

> **0.2.0, 0.3.0 and 0.4.0 have implementation plans.** Each is an ordered,
> file-by-file task list with a named test per assertion:
> [`IMPLEMENTATION/CROSS-CUTTING.md`](IMPLEMENTATION/CROSS-CUTTING.md) (stub
> removal, key provenance, Dart/isolate policy),
> [`IMPLEMENTATION/020-platform-unlock.md`](IMPLEMENTATION/020-platform-unlock.md),
> [`IMPLEMENTATION/030-key-lifecycle.md`](IMPLEMENTATION/030-key-lifecycle.md),
> [`IMPLEMENTATION/040-backup-restore-migration.md`](IMPLEMENTATION/040-backup-restore-migration.md).
> Start there rather than re-deriving the design.

> **This roadmap creates no security claim.** It describes intended work.
> What the package actually claims — and what it explicitly does not — lives in
> [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md), which must be updated *before* any
> property is asserted ([`AGENTS.md` rule 5](../AGENTS.md)). A version marked
> *current* means the code, tests and documentation live on `main`; it has not
> been independently reviewed. That happens once, in `1.0.0`.

## Version ladder

| Version | Theme | State |
| --- | --- | --- |
| [`0.1.0`](#010--first-release-everything-merged-so-far) | First release — all current work | **Current, unpublished** |
| [`0.2.0`](#020--platform-unlock) | Platform unlock and capability enforcement | Planned |
| [`0.3.0`](#030--key-lifecycle) | Key lifecycle: rotation, re-wrap, lineage | Planned |
| [`0.4.0`](#040--backup-restore-and-migration) | Backup, restore and migration | Planned |
| [`0.5.0`](#050--threshold-custody) | Threshold share custody | Planned |
| [`0.6.0`](#060--scale-and-concurrency) | Scale and concurrency | Planned |
| [`0.7.0`](#070--security-hardening) | Security hardening: KDF bounds, provider evidence, fuzzing | Planned |
| [`0.8.0`](#080--beta) | Beta: dependency audit, negative contract, end-to-end CI | Planned |
| [`0.9.0`](#090--release-candidate) | Release candidate: minimum SDK verified, Apple identity, docs polish | Planned |
| [`1.0.0`](#100--stable) | Stable: independent review, ADR freeze, semver promise | Planned |

---

## 0.1.0 — First release (everything merged so far)

**Theme:** the scaffolding plus the hardening work landed while the package was
being built. This is the first thing that would be published — it is unreleased
today.

What `main` already contains, all verified by CI run 37770096113:

- **Facade and codec.** `PqKeystore` with `put`, `use`, `delete`, `list`,
  `metadata`, `putShare`, `useShare`. PQKS v1 with strict framing, canonical
  AAD, and record-ID binding.
- **Platform channel contract v1** on all five targets — one channel name
  (`com.yardenah.pqkeystore/store`), one schema, one error vocabulary, one
  shared conformance suite. Identical `id`/`data`/`options` argument names,
  `delete` returns a bool, `listIds` implemented, `__meta__` sidecar removed.
- **Native backends.** AndroidKeyStore AES-256-GCM in `noBackupFilesDir` (PQNA
  v2 envelope, 48 KiB chunks fixing a measured API-24–28 GCM defect), Apple
  data-protection keychain (shared source, `base64url` accounts, crash-safe
  pending-item replacement), Windows DPAPI files (PQNW, ID bound into the
  entropy), Linux Secret Service (no file fallback, ever).
- **File store v1** (ADR-0010): `hex(SHA-256(ID)).pqks` names, no index,
  atomic temp-file + rename, verified `0700`/`0600`, stale-temp reclamation,
  ad-hoc legacy adoption.
- **`FallbackKeystoreBackend`:** opt-in only, triggers only on `UNAVAILABLE`,
  dual-read, migrate-on-write, `migrateToSecure()`, `.deleted` tombstones.
- **Record envelopes:** PQNA v2 (Android), PQNW (Windows), keychain item
  (Apple), Secret Service item (Linux), tombstones, file store v1 — every byte
  layout in [`FORMATS.md`](FORMATS.md).
- **Integrity gate.** `use()` recomputes the canonical AAD from the decoded
  metadata and refuses to reach the crypto adapter unless it matches the stored
  AAD and the decoded ID matches the requested one.
- **Secret lifetime as a cardinal rule** ([`AGENTS.md` rule 10](../AGENTS.md)):
  the buffer returned by `unwrap` is wiped with `secureZero` immediately after
  it is copied, on every exit path.
- **CI:** the Dart gate plus native builds and contract suites on Android
  (API 26/28/35), Windows, Linux and iOS (SwiftPM) on every push and PR.
  macOS and iOS CocoaPods build, then fail fast with an explicit missing Apple
  signing identity error.
- **Documentation:** real per-platform READMEs, a top-level README that states
  what is and is not supported, and an explicit claim boundary.

**Exit criterion to publish `0.1.0`:** maintainer decides the release tag and
publication policy (TRK-011), the declared minimum SDK pair is actually
executed once and recorded (TRK-001), and the security review (TRK-012) is at
least scoped and scheduled. Until then, `publish_to: none` stays.

---

## 0.2.0 — Platform unlock

**Theme:** let the device gate access, and stop options being backend-scoped.

This is the first genuinely new *capability* after the first release.

Today the facade cannot request a storage option at all: `PlatformStoreOptions`
is bound to the `PlatformKeystoreBackend` instance, and `PlatformUnlock` is
hard-rejected by the facade with `PolicyError`. This version closes both gaps.

- **Per-write options.** `PlatformStoreOptions` becomes an argument to `put`
  (and `putShare`), so one keystore holds records at different protection
  levels.
- **`PlatformUnlock` implemented.** Remove the facade's blanket rejection; a
  platform-unlocked record is unwrapped only after the OS releases it.
- **`PassphraseThenPlatform` actually chains.** Today it is handled as
  passphrase-only; it should run passphrase derivation *and* device
  authentication, with `Cancelled` surfaced when the user cancels.
- **Capability negotiation as a first-class API.** "Can this device enforce
  these options?" before write time. `UNSUPPORTED_OPTION` semantics stay:
  refuse, never ignore.
- **Android user presence.** `requireUserPresence` is unsupported on Android
  because it needs a `BiometricPrompt` hosted by a `FragmentActivity`. Introduce
  an activity-scoped prompt flow with a `KeyguardManager` device-credential
  fallback.

**Not included:** biometrics on Windows or Linux, TPM/Windows Hello binding,
changing `UNSUPPORTED_OPTION` into a warning.

**Exit gate:** the shared conformance suite passes on all five targets with the
new options, and the Apple legs are unblocked by a provisioned signing
identity.

---

## 0.3.0 — Key lifecycle

**Theme:** keys outlive the moment they are created.

- **Rotation.** `rotate(oldId, newId)` produces a new record, links
  `rotatedFrom`, and a documented policy for the predecessor (retain, tombstone,
  or refuse while dependents exist).
- **Re-wrap.** Change the passphrase protecting a key without re-encrypting the
  key itself and without ever exposing it to the application.
- **Lineage and version history.** Make `rotatedFrom` queryable, with
  `KeyMetadata.version` driving schema evolution.
- **Metadata schema v2** with an explicit migration rule from v1, and a
  documented policy for metadata when a record is deleted.
- **Explicit overwrite and delete semantics**, including what `delete` promises
  per platform (file store, keychain, DPAPI, Secret Service).

**Not included:** backup/restore, cross-device export, threshold ceremony.

**Exit gate:** rotation and re-wrap round-trip through every backend, with
tests asserting the predecessor's fate in each case.

---

## 0.4.0 — Backup, restore and migration

**Theme:** make records outlive one device.

- **Backup/restore API** with an explicit per-platform policy: portable
  (file store, synchronizable Apple items), device-bound (AndroidKeyStore keys,
  DPAPI user scope), and what a restore requires.
- **Record migration tooling.** A supported path from PQKS v1 to any future
  version, with version negotiation on read so an old client refuses a new
  record rather than mis-parsing it.
- **Store inspection helpers** for validating and re-sealing a store directory
  — the same checks the legacy-adoption path already performs.
- **Metadata sensitivity policy**, written down for the first time: which
  metadata fields may hold sensitive values given that PQKS stores metadata in
  cleartext.

**Not included:** cross-vendor key portability claims, silent automatic
migration.

**Exit gate:** restore on a clean device is documented and tested per platform
class; unsupported combinations fail loudly.

---

## 0.5.0 — Threshold custody

**Theme:** shares are first-class, but reconstruction is never implicit.

- **Share metadata validation.** Bound `t` and `n`, validate
  `participantIndex ∈ [0, n)`, require a ceremony id, and reject inconsistent
  metadata at `putShare` time.
- **`pqthreshold` interoperability, as a boundary.** `pqkeystore` stores opaque
  sealed shares; `pqthreshold` owns ceremony correctness and any
  reconstruction.
- **End-to-end test** against `pqthreshold` before any interoperability claim is
  made. Until that test exists the claim is withheld — this is deliberate and
  is the current state.
- **No implicit reconstruction anywhere in the facade.** A regression test
  asserts no code path reassembles shares.

**Not included:** running ceremonies, key generation, DKG.

**Exit gate:** validation tests plus one passing end-to-end `pqthreshold` test;
the claim boundary is updated only after that test passes.

---

## 0.6.0 — Scale and concurrency

**Theme:** behave predictably with many keys and large records.

- **Large-record path** measured end to end: sealing, storage, retrieval, and
  the memory peak of `use()` at the 1 MiB contract maximum.
- **Concurrency semantics per backend**, documented and tested. The file store
  already serializes per directory; the guarantee must be explicit and extended
  to the fallback and platform backends.
- **Memory-pressure behaviour**, including the Android large-heap path and how a
  1 MiB transient allocation is handled on iOS.
- **Benchmarks** for put/use/list at realistic sizes, with recorded baselines.
- **Startup cost** kept near zero for apps that never touch the keystore.

**Not included:** raising the 1 MiB record limit, streaming decryption of larger
records.

**Exit gate:** benchmarks committed with baselines.

---

## 0.7.0 — Security hardening

**Theme:** attack the thing on purpose, before someone else does.

- **KDF parameter bounds enforced before the KDF runs.** `kdfParams` is
  attacker-controlled; Argon2id cost, salt length and lane count must be
  range-checked before invoking pqforge, so a hostile record cannot trigger
  memory exhaustion.
- **Provider lifecycle evidence** (TRK-005): with exact pinned versions and
  source references, document which buffers `pqforge` and `zeroize` copy, own,
  dispose and allow to be overwritten. This is what would let the
  memory-erasure non-claims be upgraded — or, more likely, confirmed permanent.
- **Codec fuzzing** on PQKS decode, file-store parsing, and the tombstone
  parser, all required to fail closed with a typed error.
- **Negative contract coverage** for every error path: hostile IDs, records
  stored under the wrong name, truncated envelopes.

**Not included:** claiming security properties that have not been examined.

**Exit gate:** fuzzing runs in CI; the claim boundary is rewritten against the
new evidence.

---

## 0.8.0 — Beta

**Theme:** a deliberately marked, evidence-linked beta.

- **Dependency audit** of `pqforge`, `zeroize`, and the platform channels.
- **API polish from real use**: error messages, diagnostic surfaces,
  ergonomics of the capability-negotiation API added in `0.2.0`.
- **The two Apple CI legs green**, via a provisioned signing identity.
- **The declared minimum SDK pair actually executed** and recorded.
- **Tagged beta** under the approved publication policy, with docs tracking it.

**Not included:** production-readiness claims.

**Exit gate:** the published beta runs the shared contract suite on all five
platforms, and the minimum-SDK evidence is on file.

---

## 0.9.0 — Release candidate

**Theme:** the final dry run for `1.0.0`.

- **Architecture freeze (TRK-002).** ADR-0002 … ADR-0010 accepted as written, or
  explicitly deferred — no longer `Proposed`.
- **Release metadata finalised (TRK-011).** Publication policy, version scheme,
  changelog rules, archive inspection, no placeholders.
- **Claim boundary re-reviewed** against the audit scoping done in `0.8.0`.
- **Deprecation and semver policy written down.**

**Exit gate:** the release candidate is tagged, installable, and every gate in
[`TRACKER.md`](TRACKER.md) has green evidence or a maintainer-approved
disposition.

---

## 1.0.0 — Stable

**Theme:** the only version that may be called production-ready.

- **Independent security review** (TRK-012) of the release candidate by a
  reviewer independent of the implementation, with a written scope agreed before
  work starts, a finding-disposition table, and retest evidence for every
  critical/high finding.
- **Every release gate in [`TRACKER.md`](TRACKER.md) closed.**
- **Claim boundary re-reviewed** against the audit report, with residual risks
  either fixed or explicitly accepted by the maintainer.
- **Stability promise:** documented semantic versioning, a deprecation policy
  with a minimum notice period, and a compatibility contract for the platform
  channel — a v2 contract would ship as a new major version.

**Explicitly not in 1.0.0, and not planned for it:** claims of hardware-backed
key storage, complete process-memory erasure, cross-application isolation on
Linux or Windows, biometric support on desktop platforms, and implicit
threshold reconstruction.

**Exit gate:** all five release gates in [`TRACKER.md`](TRACKER.md) have
evidence; the audit report or an approved summary is retained.

---

## Release policy

Do not call the package production-ready, or publish a stable release, until
every release gate in [`TRACKER.md`](TRACKER.md) has evidence. Update
[`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md) before asserting any newly implemented
security property, and prefer under-claiming to over-claiming
([`AGENTS.md` rule 5](../AGENTS.md)).

A version may only be tagged when its own exit gate has passed and every
earlier gate remains green — a later version's progress never excuses reopening
an earlier claim.

## Current verification baseline

`tool/verify.sh` passes on Dart 3.13.4 / Flutter 3.47.5 — root and example
resolution, `dart analyze`, and **135** package tests. CI run 37770096113:
Dart, Linux, Windows, Android (API 26/28/35) and iOS (SwiftPM) green; macOS and
iOS CocoaPods build, then fail fast with an explicit "no Apple development
signing identity" error. The declared minimum SDK pair (Dart 3.12.0 / Flutter
3.24.0) has not been executed.
