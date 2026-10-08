# Roadmap

Ten releases from `0.1.0` to `1.0.0`. Each version has exactly one theme, an
explicit *not included* list, and a gate that must pass before the next version
starts.

Confirmed defects are in [`BUGS.md`](BUGS.md). Work items and release gates are
in [`TRACKER.md`](TRACKER.md). All five registered platforms are required for
v1.0.0 by [ADR-0001](adr/0001-five-platform-v1.md).

> **This roadmap creates no security claim.** It describes intended work.
> What the package actually claims — and what it explicitly does not — lives in
> [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md), which must be updated *before* any
> property is asserted ([`AGENTS.md` rule 5](../AGENTS.md)). A version marked
> *delivered* means the code, tests and documentation exist; it does not mean
> the property was independently reviewed. That happens once, in `1.0.0`.

## Version ladder

| Version | Theme | State |
| --- | --- | --- |
| [`0.1.0`](#010--scaffolding-and-channel-contract) | Scaffolding and channel contract | **Delivered** |
| [`0.2.0`](#020--storage-hardening) | Storage hardening across all five platforms | **Delivered** |
| [`0.3.0`](#030--fallback-recovery-and-record-integrity) | Fallback, recovery and record integrity | **Delivered** |
| [`0.4.0`](#040--platform-unlock) | Platform unlock and capability enforcement | **Next** |
| [`0.5.0`](#050--key-lifecycle) | Key lifecycle: rotation, re-wrap, lineage | Planned |
| [`0.6.0`](#060--backup-restore-and-migration) | Backup, restore and migration | Planned |
| [`0.7.0`](#070--threshold-custody) | Threshold share custody | Planned |
| [`0.8.0`](#080--scale-and-concurrency) | Scale and concurrency | Planned |
| [`0.9.0`](#090--security-hardening-and-beta) | Security hardening and beta | Planned |
| [`1.0.0`](#100--stable) | Stable release | Planned |

---

## 0.1.0 — Scaffolding and channel contract

**Theme:** make the package real and make the platforms agree.

- `PqKeystore` facade: `put`, `use`, `delete`, `list`, `metadata`, `putShare`, `useShare`.
- PQKS v1 record codec with strict framing, and canonical AAD generation.
- `MemoryKeystoreBackend` and an initial `FileKeystoreBackend`.
- Platform channel contract v1: one channel name (`com.yardenah.pqkeystore/store`),
  one method schema, one error vocabulary, identical on all five targets.
- Native implementations for Android, iOS, macOS, Windows and Linux.
- Shared conformance suite runnable as pure Dart and against a real device, plus
  CI on every platform.

**Not included:** any production claim, any non-default storage option, any
independent review.

**Evidence:** 135 Dart tests, native unit suites on four targets, CI run
37770096113 green for Dart, Linux, Windows, Android (API 26/28/35) and iOS
(SwiftPM).

---

## 0.2.0 — Storage hardening

**Theme:** eliminate the storage-level defects found by the first audit.

- **File store v1** (ADR-0010): files named `hex(SHA-256(ID)).pqks`, **no index**,
  atomic temp-file + rename, verified `0700`/`0600` on desktop POSIX, stale-temp
  reclamation, and in-place adoption of the legacy sanitized-name layout.
  This closes the ID-collision, index-redirection and destructive-replacement
  defect classes outright.
- **PQNA v2** on Android: records sealed as 48 KiB chunks, because AndroidKeyStore
  AES-GCM on API ≤ 28 fails tag verification for payloads above roughly 64–256 KiB.
  Records up to the 1 MiB contract maximum are readable on every supported API level.
- **PQNW** envelope on Windows with the ID bound into the DPAPI entropy, so a
  renamed file cannot decrypt.
- **Darwin keychain accounts** encoded as `base64url(UTF-8 ID)`, and `listIds`
  comparing UTF-8 bytes, because the keychain otherwise merges canonically
  equivalent IDs (NFC vs NFD `café`) into one entry.
- Android floor raised to API 26, matching what the implementation actually supports.

**Not included:** fallback storage, migration tooling, capability enforcement.

**Evidence:** bug-named regression tests in `test/file_backend_test.dart`;
on-device `OnDeviceRoundTripTest` at the chunk boundary and at 1 MiB.

---

## 0.3.0 — Fallback, recovery and record integrity

**Theme:** survive a missing secure store, and refuse to decrypt a tampered record.

- **`FallbackKeystoreBackend`** (ADR-0010): opt-in, triggers *only* on
  `UNAVAILABLE`, dual-read with the fallback copy first, migrate-on-write,
  `migrateToSecure()`, and `.deleted` tombstones so a record deleted while the
  store was down cannot resurface when it returns. Exposed through
  `BackendType.platformWithFileFallback` and `locate()`.
- **Canonical AAD enforcement**: `use()` recomputes the canonical AAD from the
  decoded metadata and refuses to call the crypto adapter unless it matches the
  stored AAD *and* the decoded ID matches the requested ID. Mismatch is
  `FormatError`; `unwrap` is never reached.
- **Secret lifetime**: the buffer returned by `unwrap` is wiped with `secureZero`
  immediately after it is copied, because `SecretBytes.fromUint8List` copies
  rather than takes ownership. Promoted to a cardinal rule,
  [`AGENTS.md` rule 10](../AGENTS.md).
- Documentation reconciled with verified behaviour, including three claim
  statements that had contradicted the code.

**Not included:** rotation, migration, backup, threshold work, any new storage option.

**Evidence:** `test/fallback_backend_test.dart`, `test/record_invariants_test.dart`,
`test/secret_lifetime_test.dart`. The wipe test was verified to *fail* when the
fix is reverted.

---

## 0.4.0 — Platform unlock

**Theme:** let the device gate access, and stop the options being backend-scoped.

This is the next version, and the first genuinely new *capability*.

Today the facade has no way to request a storage option at all: `PlatformStoreOptions`
is bound to the `PlatformKeystoreBackend` **instance**, and `PlatformUnlock` is
hard-rejected by the facade with `PolicyError`. This version closes both gaps.

- **Per-write options.** `PlatformStoreOptions` becomes an argument to `put` (and
  `putShare`) rather than backend construction state, so one keystore can hold
  records with different protection levels.
- **`PlatformUnlock` implemented.** Remove the facade's blanket rejection; a
  platform-unlocked record is unwrapped only after the OS releases it.
- **`PassphraseThenPlatform` actually chains.** Today it is handled as
  passphrase-only; it should perform passphrase derivation *and* device
  authentication, with a documented failure mode when the second factor is
  unavailable or cancelled (`Cancelled` is already in the error vocabulary).
- **Capability negotiation as a first-class API.** A helper that answers "can
  this device enforce these options?" before a write is attempted, so
  applications can degrade deliberately instead of discovering at write time.
  `UNSUPPORTED_OPTION` semantics stay exactly as they are: refuse, never ignore.
- **Android user presence.** `requireUserPresence` is currently unsupported on
  Android because it needs a `BiometricPrompt` hosted by a `FragmentActivity`.
  Introduce an activity-scoped prompt flow so the capability can be offered,
  with `KeyguardManager` fallback for device credential.

**Not included:** biometrics on Windows or Linux; TPM/Windows Hello binding;
changing `UNSUPPORTED_OPTION` into a warning.

**Exit gate:** capability negotiation plus per-write options pass the shared
conformance suite on all five targets, and the Apple legs are unblocked by a
provisioned signing identity (they are red on that alone today).

---

## 0.5.0 — Key lifecycle

**Theme:** keys outlive the moment they are created.

- **Rotation.** `rotate(oldId, newId)` producing a new record, linking
  `rotatedFrom`, and a documented policy for the predecessor (retain, tombstone,
  or refuse while dependents exist).
- **Re-wrap.** Change the passphrase protecting a key without re-encrypting the
  key itself and without ever exposing it to the application.
- **Lineage and version history.** Make `rotatedFrom` a real, queryable chain
  rather than a plain field, with `KeyMetadata.version` used for schema evolution.
- **Metadata schema v2** with an explicit migration rule from v1, and a
  documented decision on what happens to metadata when a record is deleted.
- **Explicit overwrite and delete semantics**, including what `delete` promises
  about the file store, the keychain and DPAPI respectively.

**Not included:** backup/restore, key export to other devices, threshold ceremony.

**Exit gate:** rotation and re-wrap round-trip through every backend, with
tests asserting the old record's fate in each case.

---

## 0.6.0 — Backup, restore and migration

**Theme:** make records outlive one device.

- **Backup and restore API** with an explicit per-platform policy table: what is
  portable (Apple sync-capable items, file store), what is device-bound
  (AndroidKeyStore keys, DPAPI user scope), and what restore requires.
- **Record migration tooling.** A supported path from PQKS v1 to any future
  version, with a version-negotiation contract so an old client cannot silently
  misread a new record.
- **CLI or library helpers** for inspecting, validating and re-sealing a store
  directory — the same check the legacy-adoption path performs.
- **Metadata sensitivity policy**, finally written down: which metadata fields
  may hold sensitive values given that PQKS stores metadata in cleartext.

**Not included:** cross-vendor key portability claims (they are cryptographic
problems, not custody problems), silent automatic migration.

**Exit gate:** a restore on a clean device is documented and tested for each
platform class; unsupported combinations fail loudly.

---

## 0.7.0 — Threshold custody

**Theme:** shares are first-class, but reconstruction is never implicit.

- **Share metadata validation.** Bound `t` and `n`, validate
  `participantIndex ∈ [0, n)`, require a ceremony id, and reject inconsistent
  metadata at `putShare` time.
- **`pqthreshold` interoperability**, defined as a boundary: `pqkeystore` stores
  opaque sealed shares, `pqthreshold` owns ceremony correctness and any
  reconstruction.
- **End-to-end test** against `pqthreshold` before any interoperability claim is
  made. Until that test exists, no claim is made — this is deliberate and
  currently the state.
- **No implicit reconstruction anywhere in the facade.** A regression test asserts
  that no code path reassembles shares.

**Not included:** running ceremonies, key generation, DKG.

**Exit gate:** validation tests plus an end-to-end `pqthreshold` test; the claim
boundary is updated only after that test passes.

---

## 0.8.0 — Scale and concurrency

**Theme:** behave predictably when there are many keys and large records.

- **Large-record path** measured end to end: sealing, storage, retrieval, and the
  memory peak of `use()` at the 1 MiB contract maximum.
- **Concurrency semantics per backend**, documented and tested: the file store
  already serializes per directory; make the guarantee explicit and extend it to
  the fallback and platform backends.
- **Memory-pressure behaviour**, including what happens on the Android large-heap
  path and how iOS handles a 1 MiB transient allocation.
- **Benchmarks** for put/use/list at realistic sizes, published so regressions are
  visible rather than discovered in production.
- **Startup cost**: the plugin attach path must stay cheap for applications that
  never use the keystore.

**Not included:** changing the 1 MiB record limit, streaming decryption of records
larger than the contract maximum.

**Exit gate:** benchmarks committed with recorded baseline numbers.

---

## 0.9.0 — Security hardening and beta

**Theme:** attack the thing, on purpose, before someone else does.

- **KDF parameter bounds enforced before the KDF runs.** `kdfParams` is
  attacker-controlled record data; Argon2id cost, salt length and lane count must
  be range-checked before invoking pqforge, so a hostile record cannot trigger a
  memory-exhaustion attack.
- **Provider lifecycle evidence** (TRK-005): document, with exact pinned versions
  and source references, which buffers `pqforge` and `zeroize` copy, own, dispose
  and allow to be overwritten. This is what would let the memory-erasure
  non-claims be upgraded — or, more likely, confirmed as permanent.
- **Codec fuzzing**: PQKS decode, file-store record parsing and the
  fallback tombstone parser, all required to fail closed with a typed error.
- **Negative contract tests** for every error path, including hostile IDs, records
  stored under the wrong name, and truncated envelopes.
- **Dependency audit** and a recorded **beta** release with explicit,
  evidence-linked claim wording.

**Not included:** claiming security properties that have not been independently
examined.

**Exit gate:** fuzzing runs in CI; the claim boundary is rewritten against
evidence; a tagged beta is published under the approved publication policy.

---

## 1.0.0 — Stable

**Theme:** the only version that may be called production-ready.

- **Independent security review** (TRK-012) of the release candidate by a
  reviewer independent of the implementation, with a written scope agreed before
  work starts, a finding-disposition table, and retest evidence for every
  critical/high finding.
- **Every release gate in [`TRACKER.md`](TRACKER.md) closed**, including:
  - architecture freeze — ADR-0002 … ADR-0010 **Accepted**, not `Proposed`;
  - the declared minimum SDK pair actually executed and recorded;
  - the macOS and iOS CocoaPods contract suites green under a provisioned Apple
    signing identity.
- **Claim boundary re-reviewed** against the audit report, with residual risks
  either fixed or explicitly accepted by the maintainer.
- **Stability promise**: documented semantic-versioning policy, a deprecation
  policy with a minimum notice period, and a stated compatibility contract for
  the platform channel (a v2 contract would ship as a new major version).
- **Publication policy** decided and executed under maintainer action — not by
  this roadmap.

**Explicitly not in 1.0.0**, and not planned for it: claims of hardware-backed
key storage, complete process-memory erasure, cross-application isolation on
Linux or Windows, biometric support on desktop platforms, and implicit threshold
reconstruction.

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
resolution, `dart analyze`, and **135** package tests. CI run 37770096113 on
merged `main`: Dart, Linux, Windows, Android (API 26/28/35) and iOS (SwiftPM)
green; macOS and iOS CocoaPods build, then fail fast with an explicit
"no Apple development signing identity" error. The declared minimum SDK pair
(Dart 3.12.0 / Flutter 3.24.0) has not been executed.
