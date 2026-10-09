# Upstream register — cross-repo dependencies and open work

`pqkeystore` is the **consumer** at the end of a dependency chain. This file is
the register of what it needs from the packages below it, what is already
satisfied, and what is open.

It is the coordination hub, not a specification. Every row cites the file and
line that proves its current state, so a stale row is detectable rather than
merely wrong.

## The chain

```
zeroize ──────────┐
                  ├──> pqcrypto ──┐
pqforge ──────────┼───────────────┼──> pqkeystore
                  │               │
pqthreshold ──────┴───────────────┘
        ↑
pqdga
```

Verified as of the `pqkeystore` merge `8bc0ef6` and the surveyed upstream
`main`/`develop` branches. No row below is a claim about behaviour I did not
read.

---

## Corrections to previously-stated asks

Recorded because they were wrong, and leaving them uncorrected would send
someone to do unnecessary or harmful work.

| Previously advised | Actually true | Consequence |
| --- | --- | --- |
| "`pqforge` should export `pqforge_stream_service.dart` / `pqforge_pack_service.dart`" | **Already exported**, from `lib/pqforge_io.dart:23-24`, not the core barrel | **No change needed.** `pqforge/AGENTS.md` forbids `dart:io` in the core barrel's import graph; moving these exports there would break web-safety. The existing split is correct. |
| "`pqkeystore` should reference `pqcrypto` params getters instead of hardcoding lengths" | Correct and still wanted, but ML-KEM's getters are unreachable | `DilithiumParams`/`SlhDsaParams` are exported (`pqcrypto/lib/pqcrypto.dart:42,46`); `KyberParams`/`KyberLevel` are **not** — line 38 is `show KyberKem, PqcKem`. See UQ-1. |
| "Add a typed pqdga key object for first-class import" | `pqdga` has **no** key classes; secret-bearing state is plain public `Uint8List` fields | No pqdga key type to import. See UQ-7. |

---

## Published status, verified against pub.dev

Checked via the pub.dev API, not the repository docs. The two disagree, and the
repository docs are the wrong ones.

| Package | Local checkout | On pub.dev | Consequence |
| --- | --- | --- | --- |
| `crypto_shared` | 1.0.0 (`pqthreshold/packages/crypto_shared/`) | **1.0.0**, published 2026-09-26 | Already a dependency of `pqkeystore`. `README.md:182` and `CHANGELOG.md:5-6` are stale. |
| `zeroize` | 0.2.0 (PR #1 merged) | 0.1.0 | The merged `SecretTransfer` is not usable by a dependent until 0.2.0 is published. |
| `pqcrypto` | 0.4.2 | 0.4.2 | — |
| `pqforge` | 0.4.6 → 0.4.7 (PR #26) | 0.4.6 | `Argon2Limits` is unavailable to dependents until published. |
| `pqthreshold` | 1.0.1 → 1.1.0 (PR #1) | 1.0.1 | `ShareMetadata` is unavailable until published. |
| `pqdga` | **0.1.0** | **0.1.1** | The local checkout is **behind** what is published. Reconcile before any work. |
| `pqtransport` | 0.1.0 | 0.1.0 | — |
| `swissarmyknife` | 0.1.0 | 0.1.0 | — |
| `pqkeystore` | 0.1.0-dev.1 | not published | `publish_to: 'none'` as intended. |

The published `crypto_shared-1.0.0` archive contains `lib/src/share_wrapping.dart`
with the canonical ids `threshold-share` / `pqthreshold/pqth-share-v1`, and pins
`pqthreshold: ^1.0.1` and `pqforge: ^0.4.5`. Those two pins mean `crypto_shared`
must be bumped before it can use anything added in `pqthreshold` 1.1.0 or
`pqforge` 0.4.7.

## Verified already satisfied

| Fact | Evidence |
| --- | --- |
| `pqcrypto` ML-KEM 512/768/1024 sizes `pk` 800/1184/1568, `sk` 1632/2400/3168 | `pqcrypto/lib/src/algos/kyber/params.dart` — `publicKeyBytes => 384*k+32`, `secretKeyBytes => 384*k+publicKeyBytes+64` |
| `pqcrypto` ML-DSA 44/65/87 sizes `pk` 1312/1952/2592, `sk` 2560/4032/4896 | executed against `DilithiumParams.get()`; `params.dart:116,119` |
| `pqcrypto` SLH-DSA all 12 sets `pk = 2n`, `sk = 4n` → 32/64, 48/96, 64/128 | executed against `SlhDsaParams.get()`; `params.dart:157,158` |
| `zeroize` is pure Dart, `dart:typed_data` only, one dependency (`meta`) | `zeroize/pubspec.yaml:22-23`, description states "No FFI or dart:io required" |
| `zeroize`'s `secureZeroIntList(List<int>)` covers `Int32List` and `Uint32List` | `zeroize/lib/src/core/secure_zero.dart:54` |
| `pqforge` ratcheting is web-safe (no `dart:io`, no `dart:ffi`) and analyzes clean | `grep` over `lib/src/ratchet/`; `dart analyze lib/src/ratchet/` → no issues |
| `pqkeystore`'s `use()` already zeroes the unwrap buffer | `lib/src/api/pq_keystore.dart`, AGENTS rule 10 |

---

## Work landed

Verified by the command output recorded per row. Nothing here is claimed from a
plan.

| Item | Where | Result |
| --- | --- | --- |
| UZ-1, UZ-2 — `SecretTransfer` isolate-safe transfer | [zeroize#1](https://github.com/turkananation/zeroize/pull/1) | **Merged.** `dart analyze` clean, `dart test` 203 passed (was 191). New `SecretTransfer` plus `SecretBytes.intoTransfer()`; move semantics, wipe-on-both-sides, honest limits on the runtime-owned `TransferableTypedData` buffer and per-isolate single consumption. |
| UF-1 — Argon2id cost bounds | [pqforge#26](https://github.com/turkananation/pqforge/pull/26) | **Open, mergeable.** `Argon2Limits` (iterations 1..10, `memoryPowerOf2` 10..20, lanes 1..16, salt >= 8); `unwrapKeyWithPassphrase` throws a typed `PqForgeException` naming field, observed value and range. `dart analyze` clean, 68 tests pass. `0.4.6` -> `0.4.7`. |
| UT-1, UT-2, UT-5 — share metadata, public dispose, public validators | [pqthreshold#1](https://github.com/turkananation/pqthreshold/pull/1) | **Open.** `ShareMetadata.fromBytes` reads `t`/`n`/`index`/`participantId`/`ceremonyId` without touching the scalar; `validateShareIndex` / `validateParticipantId` public; `Share.disposeSecret()` public; `SecretBuffer.use`/`mutate` windowing. `dart analyze` clean, 121 tests pass (was 101). `1.0.1` -> `1.1.0`. |
| UQ-1 — export `KyberParams` / `KyberLevel` | this repo | Implemented and analyzed in the working tree; the KAT regression is still running and the PR is **not** opened. |

## Open work, by project

Status: **open** = not started. Nothing in this table is claimed as done.

### zeroize — 0.1.0 → 0.2.0

| ID | Item | Evidence | Why it matters |
| --- | --- | --- | --- |
| UZ-1 | Add a **sendable secret transfer** primitive. `SecretBytes` cannot cross an isolate boundary: no `Isolate`, `SendPort` or `TransferableTypedData` reference exists anywhere in the package | `grep -rn "Isolate\|SendPort\|TransferableTypedData" zeroize/lib/` → no match | `pqkeystore` rule 12 currently enforces "secrets cross as plain `Uint8List`" by **discipline**. A type-level primitive moves it to a guarantee. |
| UZ-2 | Document the residual limit honestly in the new API: `TransferableTypedData.materialize()` yields a buffer that must itself be wiped, and the Dart-visible transferable buffer cannot be overwritten | Dart API reality | Prevents the new primitive from being read as a stronger guarantee than it is. |

### pqcrypto — 0.4.2 → 0.5.0

| ID | Item | Evidence | Note |
| --- | --- | --- | --- |
| UQ-1 | Export `KyberParams` and `KyberLevel` from the barrel | `lib/pqcrypto.dart:38` restricts to `show KyberKem, PqcKem` | One-line fix. ML-KEM is the only family whose derived sizes are unreachable, which is the sole reason a hand-copied length table exists in `pqkeystore`. |
| UQ-2 | Replace `lib/src/common/zeroize.dart` with `package:zeroize` | local impl at `lib/src/common/zeroize.dart:14-20` is a bare loop with **no** `@pragma('vm:never-inline')` and no opaque read anchor; `secure_zero` uses both | See the blocking conflict below. |
| UQ-3 | Drop `export 'src/common/zeroize.dart'` from the barrel, or keep it as a re-export shim | `lib/pqcrypto.dart:35` | Breaking for any importer; needs a changelog note. |
| UQ-4 | Update `AGENTS.md` "Runtime dependencies: none" | `pqcrypto/AGENTS.md:11` | The file states the current truth; it must stop asserting it. |

> **BLOCKING CONFLICT — UQ-2 needs a maintainer decision, not an agent's.**
> `pqcrypto` advertises zero dependencies as a product property, in three
> places: the pubspec `description` ("Zero dependencies"), the pubspec comment
> ("No third-party runtime dependencies: pqcrypto is pure Dart and fully
> self-contained"), and `AGENTS.md`. Adding `package:zeroize` breaks all three.
> Two defensible paths, and they are **not** equivalent:
>
> - **A — depend on `package:zeroize`.** One hardened implementation, and
>   `pqkeystore`/`pqforge`/others share exactly one zeroization semantics.
>   Costs the zero-dependency promise and raises the SDK floor from `^3.10.0`
>   to `^3.12.0` (`zeroize/pubspec.yaml:19`), because `zeroize` requires
>   `^3.12.0`.
> - **B — port the technique, keep zero dependencies.** Copy the
>   `@pragma('vm:never-inline')` writer plus the opaque read anchor from
>   `zeroize/lib/src/core/secure_zero.dart` into `pqcrypto`'s own file. Preserves
>   every stated property; costs a duplicated implementation that can drift.
>
> Recorded rather than decided. See the ask at the end of this document.

### pqforge — 0.4.6 → 0.4.7 and 0.5.0

| ID | Item | Evidence | Severity |
| --- | --- | --- | --- |
| UF-1 | **Bound the Argon2id parameters.** `iterations`, `memoryPowerOf2`, `lanes` reach `pc.Argon2Parameters` and `generator.process()` with no range check. `memoryPowerOf2: 40` requests a terabyte. The adjacent `pbkdf2Sha256` *does* validate | `lib/src/primitives/pq_primitives.dart:839-855` vs `:869` | **Security defect.** Anyone who can write one file into a store can trigger unbounded allocation before authentication. Patch release: `0.4.7`. |
| UF-2 | Land the ratcheting work currently sitting **uncommitted on `main`** | `git status`: 9 untracked files in `lib/src/ratchet/`, `example/ratchet_example.dart`, `test/pq_ratchet_test.dart`, `wiki/Ratcheting.md`, `doc/architecture/RATCHETING.md`, `doc/decisions/ADR-0003-ratcheting-and-custody-boundary.md`; 5 modified tracked files | It analyzes clean and is web-safe, but it is unversioned and unpublished. `AGENTS.md`: "Never discard unrelated user changes from a dirty worktree." Minor release: `0.5.0`. |
| UF-3 | Record the custody boundary between `pqforge`'s own `PqPassphraseKeyCustody` and `pqkeystore` | `lib/src/keys/pq_key_custody.dart:76` `PqPassphraseKeyCustody`, `:20`/`:48` store impls; it persists `wrapped.toJson()` with no AAD binding | `pqkeystore` bypasses it by calling `wrapKeyWithPassphrase` directly. That should be a decision, not an accident. |
| UF-4 | Document (or scope) the mutable process-wide `PqLatticeProviderRegistry.provider` | `lib/src/algorithms/pq_lattice_provider.dart:166` | Any code in the process can swap the lattice implementation under a custody layer. |

### pqthreshold — 1.1.0 → 1.2.0

| ID | Item | Evidence | Note |
| --- | --- | --- | --- |
| UT-1 | Provide a **metadata-only decode** for a share: read `version`, `kind`, `scheme`, `t`, `n`, `participantId`, `index`, `ceremonyId` **without** materializing the secret scalar | reaching `t`/`n`/`index`/`ceremonyId` today requires `Share.fromBytes`, which builds a live `SecretBuffer` (`lib/src/serialization/share_codec.dart:55-62`) | **This blocks a `pqkeystore` roadmap item.** 0.5.0 says "validate share metadata at `putShare` time"; that is impossible before sealing today, and doing it by unwrapping first inverts the custody model `pqthreshold`'s own `doc/TERMINAL.md:168-169` insists on. |
| UT-2 | Make share disposal reachable: `disposeSecret()` is `@internal`, `Share` does not implement `Disposable` | `lib/src/sharing/share.dart:80` | An unwrapped `Share` inside `pqkeystore` is a wipe-discipline liability under AGENTS rule 10. |
| UT-3 | ~~Publish `crypto_shared`~~ — **already published; the repo docs are stale.** `crypto_shared` **1.0.0** is live on pub.dev (2026-09-26) | Verified against the pub.dev API and the published archive, not the repo docs. `README.md:182` and `CHANGELOG.md:5-6` still call it unpublished | **Correction.** `pqkeystore` already depends on the published `crypto_shared: ^1.0.0` (`pubspec.yaml:22`). Fix the stale docs. |
| UT-6 | Bump `crypto_shared` so it can consume `pqthreshold` 1.1.0 | published `crypto_shared-1.0.0` pins `pqthreshold: ^1.0.1` | Its `unwrapShareWithPassphrase` decodes a full `Share`, materializing the scalar. With `ShareMetadata` it could read metadata without it. Needs a version bump to depend on the new API. |
| UT-4 | Settle and document the participant-index convention | `Share.index` is 1-based (`share.dart:37`, validated `1..n` at `:62-64`); `MlDsaShare.mithrilPartyId` is 0-based (`ml_dsa_share.dart:98`) | `pqkeystore`'s `ThresholdMeta.participantIndex` is currently documented `[0, n)` and is **wrong** relative to `Share`. See D-1. |
| UT-5 | Export a standalone validator for `1 <= index <= n` and the `participantId` length bound | both live inside `@internal Share.create` (`share.dart:62-64,82-86`) | `pqkeystore` would otherwise re-implement them. |

### pqdga — 0.1.0 → 0.2.0

| ID | Item | Evidence | Note |
| --- | --- | --- | --- |
| UG-1 | Secret-bearing state is **plain public `Uint8List` fields** with no ownership, no wipe, and no serialization | `SharedSecretPqdga.kemSecretKey`/`.sharedSecret`; `IdentityBasedPqdga.signatureSecretKey`; `IdentityBasedLabSession.signatureSecretKey` | A long-lived `PQDGAResult` holding `kemSecretKey` is a standing secret in the heap with no disposal path. |
| UG-2 | Decide whether `pqdga` wants any `pqkeystore` integration at all | package has no typed key type | Its README frames it as a defensive-research lab kit. Custody may simply be the application's job. Not assumed either way. |

---

## Defects in `pqkeystore`'s own merged documentation

Found while surveying upstream. These are ours, and they are wrong as merged.

| ID | Defect | Location | Fix |
| --- | --- | --- | --- |
| D-1 | `ThresholdMeta.participantIndex` documented `[0, n)`; `pqthreshold.Share.index` is **1-based** with `1 <= index <= n` | `doc/IMPLEMENTATION/CROSS-CUTTING.md` § B.4; `lib/src/api/key_metadata.dart` | Correct the documented range and add a `putShare` bounds test asserting `1..n`. |
| D-2 | Key-length table transcribed from specs rather than read from `pqcrypto` | `doc/IMPLEMENTATION/CROSS-CUTTING.md` § B.2.2 | **Now verified correct** against `pqcrypto`'s computed params (see *Verified already satisfied*). Re-express as references to `DilithiumParams`/`SlhDsaParams` getters once UQ-1 lands. |
| D-3 | Planned `KeyAlgorithm` ids for shares do not match `crypto_shared`'s existing canonical ids | `doc/IMPLEMENTATION/CROSS-CUTTING.md` § B.2.2 vs `pqthreshold/packages/crypto_shared/lib/src/share_wrapping.dart:11,14` | Adopt `threshold-share` / `pqthreshold/pqth-share-v1`. Inventing a parallel id guarantees silent disagreement. |
| D-4 | "first-class support" framing implies `pqdga` produces key objects | `doc/IMPLEMENTATION/CROSS-CUTTING.md` § B.2.4 | Rewrite: `pqdga` takes bytes in, exposes bytes out, and has no key type. |

---

## Sequencing

Dependency order, because each block is blocked by the one above it.

1. **UZ-1, UZ-2** — zeroize, no dependents changed yet. Safe to land alone.
2. **UF-1** — `pqforge` Argon2id bounds. Independent, patch-level, security-relevant. Can land in parallel with 1.
3. **UQ-1** — `pqcrypto` barrel export. Trivial, unblocks D-2's re-expression.
4. **UQ-2/3/4** — `pqcrypto` zeroization. **Blocked on the A-vs-B decision.**
5. **UF-2, UF-3, UF-4** — `pqforge` ratcheting + custody boundary.
6. **UT-1 … UT-5** — `pqthreshold`. UT-1 gates the `pqkeystore` 0.5.0 plan; UT-6 follows it.
7. **D-1 … D-4** — `pqkeystore` doc corrections. D-1 is independent and can land immediately.
8. **UG-1, UG-2** — `pqdga`, after its own maintainer decides on UG-2.

## Verification discipline

For every row: read the cited file, make the change, run the package's own
gate (`dart analyze` and `dart test` at minimum, plus that package's CI
matrix), and report the **actual** result. A row is marked done only with the
command output that shows it. No row is marked done on the basis of a plan.