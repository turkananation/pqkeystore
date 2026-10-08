# Cross-cutting work for 0.2.0

Three items that are not features but prerequisites. All three block 0.2.0:
the release cannot be tagged with an insecure stub still exported from the
public barrel, with key provenance discarded at write time, or with an
unenforced Dart/isolate policy on a path that runs Argon2id at 64 MiB.

---

# Part A — Remove `StubKeystoreCrypto` entirely

## A.1 Current state

`lib/src/crypto/stub_keystore_crypto.dart` defines `final class
StubKeystoreCrypto implements PqKeystoreCrypto` — a repeating-key XOR cipher
with a hand-rolled AAD check. It throws `StateError` on a bad passphrase,
`ArgumentError` on an unknown `wrapAlg`, and `UnsupportedError`-equivalent
`CryptoError` on `PlatformUnlock`.

Live references (all must reach zero):

| File | Reference |
| --- | --- |
| `lib/src/crypto/stub_keystore_crypto.dart` | the implementation |
| `lib/src/crypto/keystore_crypto.dart:14` | doc comment listing it as a peer of the interface |
| `lib/pqkeystore.dart:8` | public barrel warning block |
| `test/secret_lifetime_test.dart` | `_TrackedCrypto` wraps a stub |
| `test/record_invariants_test.dart` | fixture records wrapped by the stub |
| `test/fallback_backend_test.dart` | put/use round trips |
| `test/memory_backend_test.dart` | put/use round trips |
| `test/file_backend_test.dart` | put/use round trips |
| `test/platform_backend_test.dart` | options validation |
| `test/contract/platform_contract_suite.dart` | the shared suite's fixture provider |
| `example/integration_test/platform_contract_test.dart:10` | comment + fixture |
| `example/integration_test/linux_no_secret_service_test.dart:37` | `wrapAlg: StubKeystoreCrypto.wrapAlgId` |
| `example/README.md:21` | user-facing note |
| `README.md:54`, `SECURITY.md:17`, `doc/ARCHITECTURE.md:50`, `doc/CLAIM_BOUNDARY.md:41`, `doc/TRACKER.md:29,37`, `AGENTS.md` rule 8 | prose that must change, not just be deleted |

## A.2 Target state

The class, the file, and every reference are gone. There is exactly one
`PqKeystoreCrypto` implementation in the repository:
`PqForgeKeystoreCrypto`. Tests that need a synthetic ciphertext build it with
`PqForgeKeystoreCrypto` over throwaway bytes, not with a weaker cipher.

This is a **deliberate** loss of a cheap fixture, accepted because:

- The stub was the only cipher in the tree that could produce a record without
  invoking Argon2id. Every `put` in the suite currently costs a 64 MiB KDF.
  Replacement fixtures must not reintroduce a weak *production-visible* path to
  avoid that cost.
- The distinction being drawn is *fixture scope*, not *crypto strength*: a
  test double belongs in `test/`, and `test/` never ships.

## A.3 Change list

Ordered. Each task is independently verifiable.

**A-1. Add a test-only deterministic fixture.**

New file `test/support/test_crypto.dart`:

- `final class TestRecordCrypto implements PqKeystoreCrypto` — **lives under
  `test/`**, is never exported from `lib/`, and carries a file-level comment:
  *"Structure fixture for tests. Not cryptographically sound. Not reachable
  from `package:pqkeystore`'s public barrel."*
- `wrap` must reproduce the stub's wire contract exactly enough that
  `test/record_invariants_test.dart` keeps passing: it returns
  `(ciphertext, nonce, wrapAlg: 'test/aead/v1', kdfParams: null)` where
  `ciphertext` is `plaintext XOR a fixed 32-byte key derived from the AAD` and
  `nonce` is 12 zero bytes.
- It must still be *strict*: mismatched AAD length → `CryptoError`; empty
  passphrase → `CryptoError`; `PlatformUnlock` → `CryptoError`. The stub threw
  `StateError`/`ArgumentError`, which the facade silently converted into
  `KsFailure(CryptoError(...))` via its catch-all. The replacement throws the
  typed errors directly, which is strictly better and is the behaviour the
  tests should assert.
- `unwrap` must be the inverse and must accept only `wrapAlg == 'test/aead/v1'`.

**A-2. Repoint every test fixture.**

One-line import + constructor swap per file listed in A.1. No test logic changes
beyond that.

- `test/secret_lifetime_test.dart`: `_TrackedCrypto` keeps its role as the
  buffer-identity probe ([`AGENTS.md`](../../AGENTS.md) rule 10) and simply
  delegates `wrap`/`unwrap` to `TestRecordCrypto`. The regression assertions on
  `plaintext` being all-zero must be **byte-for-byte unchanged** — the point of
  that test is that it keeps failing when the wipe is removed, so touching it
  invalidates the evidence.
- `test/contract/platform_contract_suite.dart`: the suite takes a
  `PqKeystoreCrypto` parameter already. Verify the call sites pass
  `TestRecordCrypto` and that **no** suite assertion depends on the stub's
  specific error *classes*; where it does, assert on the typed error instead.

**A-3. Delete the file and the export path.**

- `git rm lib/src/crypto/stub_keystore_crypto.dart`
- `lib/pqkeystore.dart`: delete the warning block; re-check the file still
  documents that `PqForgeKeystoreCrypto` is the only adapter and that adapter
  presence is not a production-readiness claim
  ([`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md)).
- `lib/src/crypto/keystore_crypto.dart:14`: replace the peer list with a
  sentence pointing at `PqForgeKeystoreCrypto`.

**A-4. Replace the prose.** Every row of A.1's prose column must end up in one
of two states: the stub is gone, so the sentence is deleted; or the sentence
asserted something still true, so it is rewritten without the stub. Notably:

- `AGENTS.md` rule 8 is **replaced** by rule 11 (Part B), which forbids weak
  fixtures in `lib/` instead of warning about one in `lib/`.
- `doc/CLAIM_BOUNDARY.md:41` loses the stub sentence and keeps the real claim:
  the adapter exists, its provider behaviour is unverified, and adapter
  presence is not production readiness.
- `doc/TRACKER.md` TRK-005 keeps its substance but loses the stub clause.

**A-5. Prove the removal is complete.**

```
grep -rn "StubKeystoreCrypto\|stub_keystore_crypto" lib/ test/ example/ doc/ *.md
```

must return only lines in `doc/IMPLEMENTATION/CROSS-CUTTING.md` (this file) and
`CHANGELOG.md`'s 0.2.0 entry. Add that `grep` to `tool/verify.sh` as a hard
failure so it cannot come back.

## A.4 Test plan

| Test | File | Assertion |
| --- | --- | --- |
| No stub in `lib/` | `test/no_insecure_fixtures_test.dart` | Walks `lib/` and fails on any `implements PqKeystoreCrypto` whose class name is not `PqForgeKeystoreCrypto`. Skipped from `lib/` paths only. |
| No stub in tests | same file | Same walk over `test/` and `example/`, but permits `TestRecordCrypto` and fails on anything else implementing the interface. |
| Fixture is strict | `test/support/test_crypto_test.dart` | `wrap`/`unwrap` round-trip; wrong AAD length, empty passphrase and `PlatformUnlock` each throw `CryptoError`. |
| Existing evidence intact | `test/secret_lifetime_test.dart` | Unchanged. Re-run the "revert the wipe, watch it fail" procedure from rule 10 before signing off. |

## A.5 Exit gate

`grep` above returns nothing outside this document and `CHANGELOG.md`; all
135 pre-existing tests still pass, unchanged in count where they were pure
fixture swaps.

## A.6 Non-goals

- Not building a general "insecure" mode for demos. If the example needs cheap
  material, it uses `PqForgeKeystoreCrypto` with a short passphrase.
- Not claiming the removal improves production security. It removes a footgun
  and an export; it does not harden any live path.
- Not touching `PqForgeKeystoreCrypto`'s algorithm. `wrapAlgId` stays
  `pqforge-argon2id-aes-256-gcm-v1`; Part C's KDF bounds are about validating
  parameters *before* the KDF runs, not about changing them.

---

# Part B — First-class key material and provenance

## B.1 Current state

`PqForgeKeystoreCrypto.wrap` labels **every** record identically:

```dart
final key = PqExportedKey(
  kind: 'pqkeystore-opaque-key',
  algorithmId: 'pqkeystore/plaintext-v1',
  bytes: secretPlaintext.use(Uint8List.fromList),
  keyId: base64Encode(aad),
);
```

Consequences that matter:

- An ML-KEM-768 secret key, an X25519 key, an Ed25519 key, a P-256 key, a
  `pqthreshold` share and a `pqdga` transport identity all become
  indistinguishable inside the envelope. The KDF params echo the constant back,
  so nothing downstream can tell them apart either.
- `KeyMetadata.algorithm` is a free-form `String` on the Dart side, and it is
  covered by the canonical AAD — so it *is* authenticated — but nothing
  validates it, and nothing ties it to the bytes actually stored.
- `KeyKind` ([`lib/src/api/key_kind.dart`](../../lib/src/api/key_kind.dart)) has
  13 values, all of them **secret or share** material. There is no public-key
  member, yet `pqforge keygen` emits public keys for every algorithm
  ([`PqKeyKind.kemPublic` / `signaturePublic` in `pqforge`](https://pub.dev/packages/pqforge)),
  and `pqthreshold` and `pqdga` both work with public keys.
- `KeyKind` is a plain `enum` with `bool get isThreshold`. No `wireName`, no
  `fromName`, so the canonical AAD encodes it by `KeyKind.values.byName(...)`,
  which throws `ArgumentError` on an unknown value — surfaced as
  `KsFailure(FormatError)` by the catch-all, not as a typed parse failure.

## B.2 Target state

Three properties, all of which are custody properties rather than
cryptographic ones:

1. **Provenance is preserved.** The algorithm identity and origin of stored
   bytes survive the round trip, inside the envelope *and* in metadata.
2. **Every artifact pqforge/pqcrypto/pqdga/pqthreshold can produce has a
   `KeyKind` and a registered algorithm id.** Public keys included.
3. **Metadata is validated against the bytes.** A record whose `kind`/
   `algorithm` contradicts the stored length or the recorded key shape is
   rejected at read time, before unwrap.

### B.2.1 New `KeyKind` members

Additive only — existing values keep their names and ordinals so v1 canonical
AADs keep validating.

```dart
enum KeyKind {
  mlKemSecret, mlKemPublic,
  mlDsaSecret, mlDsaPublic,
  slhDsaSecret, slhDsaPublic,
  classicalX25519, classicalX25519Public,
  classicalEd25519, classicalEd25519Public,
  classicalEcdsaP256, classicalEcdsaP256Public,
  hybridKeyset,
  thresholdShare, thresholdPublic, thresholdPrivate,
  dgaMaterial, dgaTransportKey,
  transportIdentity,
  sessionEphemeral,
  wrappedBlob,
}
```

Add `String get wireName` (identical to `name` today; the indirection exists so
a future rename need not break records) and `static KeyKind fromName(String)`,
and keep `isThreshold` true for `thresholdShare`, `thresholdPublic` and
`thresholdPrivate`.

**Renaming is a breaking change.** The `classicalX25519` → `classicalX25519Secret`
split changes wire values; therefore the whole change ships in 0.3.0 alongside
metadata v2 ([`030-key-lifecycle.md`](030-key-lifecycle.md)), not in 0.2.0. In
0.2.0 only the *additive* members and the `wireName`/`fromName` plumbing land.
That split is deliberate and is the reason this Part has two milestones.

### B.2.2 Algorithm registry

New file `lib/src/api/key_algorithm.dart`:

```dart
/// A registered algorithm identity for stored key material.
///
/// Every algorithm id written into [KeyMetadata.algorithm] must be registered
/// here. Unregistered ids are rejected at write time, so a record can never
/// carry an algorithm this build cannot validate.
final class KeyAlgorithm {
  const KeyAlgorithm({
    required this.id,
    required this.kinds,
    required this.publicKeyLengths,   // may be empty for secret-only kinds
    required this.secretKeyLengths,
    required this.pqforgeKeyKind,     // one of PqKeyKind.* from package:pqforge
  });

  final String id;
  final Set<KeyKind> kinds;
  final Set<int> publicKeyLengths;
  final Set<int> secretKeyLengths;
  final String pqforgeKeyKind;
}

/// The registry. `registry` is a lookup; `resolve` throws [PolicyError] with a
/// message naming the unknown id rather than returning null.
const Map<String, KeyAlgorithm> registry;
KeyAlgorithm resolve(String id);
```

Registered ids, with the parameter sets each accepts. Lengths are exact byte
lengths of the raw secret/public key, not the DER/SPKI encoding:

| `algorithm` id | `KeyKind`s | public | secret |
| --- | --- | --- | --- |
| `ml-kem-512` / `768` / `1024` | `mlKemPublic`, `mlKemSecret` | 800 / 1184 / 1568 | 1632 / 2400 / 3168 |
| `ml-dsa-44` / `65` / `87` | `mlDsaPublic`, `mlDsaSecret` | 1312 / 1952 / 2592 | 2560 / 4032 / 4896 |
| `slh-dsa-128f/192f/256f` (+ other FIPS 205 sets, as emitted) | `slhDsaPublic`, `slhDsaSecret` | 2n | per FIPS 205 |
| `x25519` | `classicalX25519Public`, `classicalX25519` | 32 | 32 |
| `ed25519` | `classicalEd25519Public`, `classicalEd25519` | 32 | 32 |
| `ecdsa-p256` | `classicalEcdsaP256Public`, `classicalEcdsaP256` | 65 (uncompressed SEC1) | 32 |
| `hybrid-pq-classical/v1` | `hybridKeyset` | variable | variable |
| `threshold-share/v1` | `thresholdShare`, `thresholdPrivate` | variable | variable |
| `dga-transport/v1` | `dgaMaterial`, `dgaTransportKey` | variable | variable |
| `opaque/v1` | `wrappedBlob`, `sessionEphemeral`, `transportIdentity` | — | any |

> **Verify these numbers against `pqforge`'s own tables before writing the
> registry.** They are transcribed from the FIPS 203/204/205 and RFC 7748/5656
> specifications as `pqforge` implements them; `test/key_algorithm_registry_test.dart`
> is the place to pin them, by generating a real keypair per id with `PqForge`
> and asserting `bytes.length` is in the registered set. A registry entry that
> disagrees with the generator is a bug in the registry, caught by that test,
> not a silent mis-validation.

`opaque/v1` is the escape hatch and it is the *only* kind that accepts any
length. It must be the algorithm for anything whose shape cannot be checked;
`pqkeystore` does not parse key material ([`AGENTS.md` rule 3](../../AGENTS.md)), it
records what it was told and enforces that the claim is consistent.

### B.2.3 Provenance in the envelope

`PqForgeKeystoreCrypto.wrap` gains an `algorithm` parameter (Part B lands with
metadata v2, so this is 0.3.0 work) and stops using constants:

```dart
PqExportedKey(
  kind: algorithm.pqforgeKeyKind,          // 'kem-secret', 'signature-secret', …
  algorithmId: algorithm.id,               // 'ml-kem-768', 'x25519', …
  bytes: …,
  keyId: base64Encode(aad),
)
```

and `kdfParams` stops echoing the constant — `keyKind` and `algorithmId` now come
back from the envelope. `unwrap` compares the stored `algorithmId` against the
`KeyMetadata.algorithm` supplied by the caller and throws `CryptoError` on
mismatch, before the KDF runs. That check is cheap, and it means a record
relabelled by anyone who can rewrite the file but not the AAD is refused.

### B.2.4 Public import surface

New file `lib/src/api/key_import.dart`, exported from the barrel:

```dart
/// Adapters that turn another package's key object into storeable bytes.
///
/// Each method copies out of the source object and immediately wipes the
/// intermediate buffer ([AGENTS.md] rule 10). None of them retain a reference
/// to the caller's key.
extension type PqForgeKeys on PqForgeKeysImport { … }
```

Concretely, static factories on `PqKeystore`:

- `PqKeystore.metadataForPqForgeKey(PqKeyPair, {required KeyId id, String? purpose})`
- `PqKeystore.metadataForPqExportedKey(PqExportedKey, {required KeyId id, …})`
- `PqKeystore.metadataForPqWrappedKey(PqWrappedKey, {required KeyId id, …})`
- `PqKeystore.metadataForThresholdShare(…)` — already effectively exists via
  `ThresholdMeta`; name it consistently with the others.
- `PqKeystore.metadataForDgaKey(…)` — takes the `pqdga` transport/private key
  bytes plus the identifier the DGA derived them from.

They return `KeyMetadata` only; they do not write. Writing stays
`keystore.put(metadata, bytes, unlock)`, so a caller can inspect the metadata
before any secret exists in the store's hands.

### B.2.5 The `pqforge keygen` path

`pqforge keygen` (`--classical`, `--classical-only`, `--no-classical`,
`--slh-dsa`, `--slh-dsa-only`, `--no-slh-dsa`, `--out-dir`, `--argon-*`,
`--wrap-concurrency`) writes JSON key files. First-class support means a
documented, tested procedure:

1. Run `pqforge keygen --out-dir keys/`.
2. Read the JSON with `PqExportedKey.fromJson`.
3. Build `KeyMetadata` with the matching registered `algorithm` id.
4. `put(metadata, exported.bytes, PassphraseUnlock(passphrase))`.

`test/pqforge_keygen_test.dart` executes exactly that against the installed
`pqforge` for at least one id from each of `ml-kem`, `ml-dsa`, `slh-dsa`, `x25519`,
`ed25519`, `ecdsa-p256` and `hybrid`, and asserts each round-trips through
`use()`. That test is the definition of "first-class" — it is not first-class
until that test exists.

**A wrapped key from the CLI is not a `PqExportedKey`.** `pqforge keygen`
with a passphrase emits `PqWrappedKey` JSON. Two supported treatments, both
tested:

- *Unwrap locally, store the secret* — simplest, but the passphrase-based
  wrapping is undone in application memory before re-wrapping under the
  keystore's own protection. Documented as an explicit cost.
- *Store the wrapped key as opaque bytes* — `KeyKind.wrappedBlob` with
  `algorithm: 'opaque/v1'`, storing the `PqWrappedKey` ciphertext and salt
  verbatim. No plaintext secret ever reaches the store. **Preferred**, and the
  only one the example may use.

## B.3 Change list

Ordered; B-1 through B-3 are 0.2.0, B-4 onward is 0.3.0 with metadata v2.

- **B-1 (0.2.0)** `lib/src/api/key_kind.dart`: add the public-key and
  `thresholdPrivate`/`dgaTransportKey` members **appended after `wrappedBlob`**
  so existing ordinals are untouched. Add `wireName` and `fromName`. Change the
  canonical AAD encoder to use `wireName` — for v1 records the emitted string is
  byte-identical, which `test/canonical_aad_test.dart` must prove.
- **B-2 (0.2.0)** `lib/src/api/key_algorithm.dart`: the registry and
  `resolve()`, with the table in B.2.2.
- **B-3 (0.2.0)** `PqKeystore.put`: call `resolve(metadata.algorithm)` before
  anything else. Unknown id → `KsFailure(PolicyError)`. Then validate
  `metadata.kind ∈ algorithm.kinds` → else `PolicyError`. Then, when the
  algorithm has exact lengths and the kind is not `opaque/v1`, assert
  `plaintext.length` is in the registered set → else `PolicyError`. All three
  happen **before** the backend is touched and before the KDF runs.
- **B-4 (0.3.0)** Metadata v2 carries `kind` and `algorithm` as today plus the
  envelope provenance; `PqForgeKeystoreCrypto.wrap` uses `algorithm.pqforgeKeyKind`
  and `algorithm.id`; `unwrap` cross-checks.
- **B-5 (0.3.0)** `lib/src/api/key_import.dart` and the `metadataFor*`
  factories.
- **B-6 (0.3.0)** Rename `classicalX25519` → `classicalX25519Secret` and friends,
  under the v2 metadata migration so old records keep loading.

## B.4 Test plan

| Test | File | Assertion |
| --- | --- | --- |
| Registry matches reality | `test/key_algorithm_registry_test.dart` | For each registered id, generate a keypair with `PqForge` and assert both `publicKey.length` and `secretKey.length` are in the registered sets. Fails loudly if a length is wrong. |
| Unknown algorithm refused | `test/key_algorithm_registry_test.dart` | `put` with `algorithm: 'aes-128-ctr'` → `KsFailure(PolicyError)`, backend untouched. |
| Kind/algorithm mismatch refused | same | `kind: KeyKind.mlKemSecret` with `algorithm: 'x25519'` → `PolicyError`. |
| Wrong length refused | same | `kind: KeyKind.classicalX25519` with 31 bytes → `PolicyError`. |
| `opaque/v1` accepts anything | same | `KeyKind.wrappedBlob` with a 10 KiB blob → accepted. |
| AAD unchanged | `test/canonical_aad_test.dart` | Golden vectors for v1 records are byte-identical before and after B-1. |
| Provenance survives | `test/key_provenance_test.dart` | Put under each id, read `kdfParams` back, assert `keyKind`/`algorithmId` equal the registry values and not the old constants. |
| Provenance is enforced | same | Rewrite `algorithmId` inside `kdfParams` (AAD preserved) → `use` returns `CryptoError` and `unwrap` was never reached. |
| CLI interop | `test/pqforge_keygen_test.dart` | The seven-algorithm procedure from B.2.5, both treatments. |

## B.5 Exit gate

`PqForge`, `pqcrypto`, `pqthreshold` and `pqdga` material can be written and read
back with correct, enforced provenance; no code path can write a record whose
`kind` and `algorithm` contradict each other or contradict the byte length.

## B.6 Non-goals

- No key *generation* in `pqkeystore`. Generation belongs to `pqforge`
  (rule 3). `pqkeystore` imports, stores, and enforces.
- No cryptographic parsing of key material. Length and identity checks only.
- No claim that storing a `pqforge`-wrapped key blob as `opaque/v1` preserves
  any post-quantum property — it preserves the ciphertext, nothing more.
- `pqdga` is not a dependency of `pqkeystore` (rule 3). `metadataForDgaKey`
  takes bytes plus an identifier string; it never links against the package.

---

# Part C — Dart and isolate policy

## C.1 Current state

`pubspec.yaml` declares `sdk: '>=3.12.0 <4.0.0'`. The code uses sealed classes
(`UnlockMethod`, `KeyMetadata` as `final class`), switch expressions
([`platform_options.dart`](../../lib/src/backend/platform_options.dart)), records
and named parameters, and `const` constructors. That is a good baseline. There is
no written policy, so nothing prevents a future contributor from introducing a
legacy idiom, and there is no decision recorded about isolates at all.

The isolate question is not hypothetical. **`pqforge` is pure Dart**: no
`dart:ffi` anywhere in it, with `pqcrypto`, `pointycastle` and `cryptography` as
its only dependencies, and a documented note that "every lattice operation runs
as pure-Dart scalar NTT arithmetic in `pqcrypto`". Argon2id at the defaults this
repository already uses therefore allocates and burns CPU **on the caller's
isolate**:

| Parameter | Default | Value |
| --- | --- | --- |
| `iterations` | 2 | (`PqForgeKeystoreCrypto.unwrap` default, and `pqforge keygen --argon-iterations`) |
| `memoryPowerOf2` | 16 | 2¹⁶ KiB = **64 MiB** |
| `lanes` | 4 | |

64 MiB of Argon2id on the UI isolate per `put` and per `use` is a frame-dropping
event on any Flutter app. This is the single most important performance fact in
the repository and it belongs in writing, not in a maintainer's memory.

## C.2 Target state

### C.2.1 Modern Dart is the default, not an option

Required in new and modified code:

- `sealed` + pattern-matched `switch` for closed hierarchies. Where a hierarchy
  may need third-party extension, use `abstract interface class`.
- Records for multi-value returns (`({Uint8List ciphertext, …})`), not positional
  tuples. Named fields are self-documenting at call sites and at the boundary
  where they are destructured.
- `final` class for anything not meant to be extended or implemented. It is
  already used (`PqKeystore`, `KeyMetadata`, `PlatformStoreOptions`) and is what
  makes the closed hierarchies genuinely closed.
- `const` constructors on every immutable value type; `const` collections and
  `const` constructors throughout the public API so callers can build defaults
  at compile time.
- Enhanced enums with members, `switch` over enum values without `default:`, and
  exhaustive pattern matching.
- Extension types for zero-cost wrapper types over a single underlying
  representation (`KeyId`, `TransferableRecord`).
- Collection `if`/`for` elements, spread, `late final` only where the value is
  assigned exactly once and only in the same file, and `records`/`patterns`
  destructuring in `await`/`try` sites.
- No `new` keyword, no `List<int>` where `Uint8List` is meant, no raw
  `catch (e)` where the type is known, no string concatenation for paths
  (`package:path` is already available transitively — add it explicitly if used).

**Not required, and not to be introduced without evidence:** extension types
over multi-field shapes, `sealed` types in the public API purely for
pattern-matching ergonomics where the set is genuinely open to extension, or
macro-generated code. "Use the newest feature available" is not the goal; "do
not reach for an older, less safe idiom when the current one is available and
clearer" is.

### C.2.2 Isolate policy

**When to isolate.** Isolate any `put`, `use`, `rewrap` or `rotate` whose
`UnlockMethod` causes a `PqForgeKeystoreCrypto.wrap`/`unwrap`, i.e. any
passphrase-based operation. They are synchronous CPU-and-memory work behind an
already-`async` facade, so isolating them changes nothing about the API and
everything about frame stability.

**What it does and does not buy.** Isolates give the UI isolate its time back.
They do **not** reduce peak memory: the worker allocates its own 64 MiB Argon2id
block, so a device with 256 MiB available is just as constrained. Any
documentation implying isolates make large KDFs cheap is wrong and must not be
written. This is the honest framing and it belongs in
[`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md) as an explicit non-claim too.

**The mechanism.** `Isolate.run` is the right primitive here: no
`ReceivePort` bookkeeping, result returned directly, and it is available from
Dart 2.19 — far below this package's floor.

- The work must be a top-level or static function (or an extension on it).
  Closures capturing non-sendable state do not send.
- Arguments and results must be sendable. **Secrets cross the boundary as plain
  `Uint8List`, never as `SecretBytes`** — `package:zeroize` has no isolate
  support at all (no `SendPort`, `Isolate` or `Transferable` reference
  anywhere in it), so a `SecretBytes` is at best not sendable and at worst
  arrives with its wipe discipline intact but its identity broken.
- Prefer `TransferableTypedData` for the ciphertext (large, not secret) and a
  plain copy for the plaintext (secret, must be wipeable). Wipe the source
  buffer immediately after constructing the transferable, per rule 10.
- Wipe on **both** sides. The worker's copy is wiped in the worker's `finally`;
  the caller's copy is wiped in the caller's `finally`. A leak on either side
  is a leak.
- On the native platform backends, `unwrap` is dominated by the channel call,
  not by Dart CPU work — the KDF there is native. Do **not** add an isolate to
  `PlatformKeystoreBackend` paths; it would add a hop and buy nothing.
- `compute()` from `package:flutter/foundation.dart` is acceptable for a
  top-level synchronous batch, but it is deprecated in favour of `Isolate.run`
  and adds nothing over it here. Prefer `Isolate.run`.

**Where the decision lives.** New file `lib/src/internal/isolate_policy.dart`
with a single internal predicate and no public surface:

```dart
/// Whether [operation] must be executed off the caller's isolate.
///
/// Only true for the pqforge-backed passphrase paths, which run Argon2id at
/// 64 MiB in pure Dart on the caller's isolate. Native platform backends are
/// false: their work is already off-thread and an extra hop would only add
/// latency.
bool requiresIsolate(CryptoOperation operation);
```

`CryptoOperation` is an internal enum with `wrap`, `unwrap`, `rewrap`. Unit-test
it exhaustively — the enum has three members, and the test is 8 lines. Its value
is that a *future* backend author reads one predicate instead of guessing.

### C.2.3 KDF parameter bounds

Tracked as 0.7.0 work in [`../ROADMAP.md`](../ROADMAP.md), but the code change is
one function and it belongs with Part C because it is the same CPU/memory
concern:

`kdfParams` is attacker-controlled. `PqForgeKeystoreCrypto.unwrap` currently
passes `iterations`, `memoryPowerOf2` and `lanes` straight from the record into
`PqWrappedKey`. A hostile record claiming `memoryPowerOf2: 30` requests 1 GiB
before authentication is even attempted — a memory-exhaustion denial of service
reachable by anyone who can write one file into the store directory.

Bounds, agreed with `pqforge`'s defaults and enforced **before** the KDF runs:
`iterations ∈ [1, 10]`, `memoryPowerOf2 ∈ [10, 20]`, `lanes ∈ [1, 16]`,
`salt.length ≥ 16`. Out of range → `FormatError` naming the parameter and both
observed and permitted range, never `CryptoError` (this is a malformed record,
not a failed decryption).

## C.3 Change list

- **C-1** Write the C.2.1 and C.2.2 sections into
  [`AGENTS.md`](../../AGENTS.md) as rules 12 and 13 (Part A's rule 11 replaces
  the old rule 8).
- **C-2** `lib/src/internal/isolate_policy.dart` + `test/isolate_policy_test.dart`.
- **C-3** Move `PqForgeKeystoreCrypto.wrap`/`unwrap` bodies into top-level
  `_wrapInIsolate`/`_unwrapInIsolate` functions and dispatch through
  `requiresIsolate`. **The buffers handed to the isolate must be the same
  instances `secret_lifetime_test.dart` currently observes** — verify by running
  that test before and after; if `plaintext` stops being the buffer the test
  captured, rule 10's evidence is broken and the change is wrong.
- **C-4** Add `_validateKdfParams` and call it at the top of `unwrap`. Add the
  bounds table to [`../FORMATS.md`](../FORMATS.md).
- **C-5** Add the "isolates do not reduce peak memory" non-claim to
  [`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md).

## C.4 Test plan

| Test | File | Assertion |
| --- | --- | --- | --- |
| Policy is exhaustive | `test/isolate_policy_test.dart` | All three `CryptoOperation` members map as specified. |
| Frames are not dropped | `test/perf/isolate_offload_test.dart` | Tag-gated (`@Tags(['perf']`), skipped in the default run). Times 20 passphrase `use()` calls with and without the isolate, asserts the on-isolate path blocks an `EventQueue` timer measurably longer. Records numbers in the PR; the assertion is comparative, not an absolute FPS threshold, because absolute numbers are machine-dependent and would be a flaky claim. |
| Existing wipe evidence survives | `test/secret_lifetime_test.dart` | Unchanged assertions, and the "revert the wipe, watch it fail" procedure re-run after C-3. |
| Hostile KDF params refused | `test/kdf_bounds_test.dart` | `memoryPowerOf2: 30`, `iterations: 0`, `lanes: 64`, 8-byte salt → each `KsFailure(FormatError)` with the parameter named; `unwrap` never invoked (assert with the `_TrackedCrypto` probe). |
| Legal extremes still work | same | `iterations: 1, memoryPowerOf2: 10, lanes: 1` round-trips. |

## C.5 Exit gate

Rules 11–13 exist in `AGENTS.md`; the isolate policy is one tested predicate;
passphrase KDF work runs off the UI isolate; hostile KDF parameters are refused
before allocation; rule 10's regression tests still pass unmodified.

## C.6 Non-goals

- Not claiming any frame-rate or latency improvement as a security property, and
  not putting a number in the README that CI cannot reproduce on every machine.
- Not reducing peak memory. That needs a smaller `memoryPowerOf2`, which is a
  KDF policy decision for 0.7.0 with `pqforge`, not an isolate decision.
- Not moving native platform-backend calls onto isolates.
- Not requiring Dart 3.13/Flutter 3.47 (the versions this was verified on). The
  floor stays 3.12/3.24, and TRK-001 still has to actually execute it once.