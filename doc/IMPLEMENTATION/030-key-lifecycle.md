# 0.3.0 — Key lifecycle

`rotate`, `rewrap`, lineage queries, metadata schema v2 and its migration, and
the provenance half of
[`CROSS-CUTTING.md`](CROSS-CUTTING.md) Part B (`B-4` through `B-6`).

The theme is that keys outlive the moment they are created. A key in a custody
layer is not a value you write once; it is a value with a history. Today
`KeyMetadata` already has `version` and `rotatedFrom` fields and **no API that
ever sets either** — the schema anticipates this release, and this release is
what fills it in.

---

## 1. Current state

### 1.1 Dead schema, no API

`lib/src/api/key_metadata.dart`:

- `this.version = 1` — a default, never written by a caller, never compared
  against anything.
- `this.rotatedFrom` — parsed from JSON if present, settable by a caller, and
  **never validated**: it can point at itself, at a nonexistent key, at a key of
  a different algorithm, or at a key created later.
- `toJson()` emits `version` always and `rotatedFrom` when non-null.
- No `rotate`, no `rewrap`, no lineage query exists anywhere in `PqKeystore`.

### 1.2 The AAD is version-sensitive, and nothing versions it

`canonicalAad()` (`lib/src/crypto/canonical_aad.dart`) is `KeyMetadata.toJson()`
serialized with recursively sorted keys. Because `version` is a field, it is
inside the AAD. So a record written as `version: 1` has an AAD that will **not**
match a recomputation from a `version: 2` metadata object — and
`_validateRecordIdentity` (added in `f202d75`, BUG-005) rejects exactly that
mismatch with `FormatError`.

That is correct behaviour and it is a trap: metadata v2 cannot be introduced by
changing what `toJson()` emits for existing records. It must be introduced with
an explicit, version-aware AAD function.

### 1.3 `KeyKind` rename would break every record

`classicalX25519` is the wire value in every existing record's AAD. Renaming it
to `classicalX25519Secret` (§B.6) changes the AAD byte-for-byte and orphans every
v1 record. This is why the rename is 0.3.0 work and not 0.2.0 work.

### 1.4 No overwrite semantics

`put` writes whatever is at the ID. There is no create-only, no
must-not-exist, no replace. Two `put` calls with the same ID silently produce
two unrelated records with the same metadata, and the second wins. For a
custody layer this is a footgun, not a feature.

### 1.5 `delete` has no cross-platform contract

`delete` returns a bool. What it does to the material differs per platform:
`FileKeystoreBackend` unlinks, the Darwin keychain deletes the item, Windows
removes the file, Secret Service deletes the collection entry. None of this is
written down, and `use()` on a deleted key returns `NotFound` for reasons the
caller cannot distinguish from a never-existed key.

---

## 2. Target state

### 2.1 Version-aware canonical AAD

`canonicalAad` gains an explicit version parameter with a default, so every
existing call site keeps compiling and keeps producing identical bytes:

```dart
/// Canonical AAD for a record at [version].
///
/// The function is versioned, not the JSON: v1 must reproduce the byte sequence
/// produced before v2 existed, or every existing record fails its own identity
/// check on read. [KeyMetadata.version] selects which encoder runs.
///
/// Throws [PolicyError] for an unknown version.
Uint8List canonicalAad(KeyMetadata metadata, {int version = 1});
```

- `version: 1` → exactly today's `toJson()` + recursive key sort. Byte-identical
  by construction; `test/canonical_aad_test.dart`'s golden vectors are the proof
  and must not be regenerated.
- `version: 2` → §2.2's field set.

Do **not** "fix" the v1 encoder to drop nulls or reorder. It is a wire format
now, not a serialization convenience.

### 2.2 Metadata schema v2

New fields, all optional, all covered by the v2 AAD:

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | `int` | Always `2`. The v1 default of `1` stays for reading. |
| `kind`, `algorithm` | as v1 | Now validated against `KeyAlgorithm` from `lib/src/api/key_algorithm.dart` at both write and read. |
| `provenance` | `Map<String, String>` | Free-form, closed set of keys enforced by the codec: `origin` (`'pqforge'`, `'pqcrypto'`, `'pqthreshold'`, `'pqdga'`, `'imported'`), `generator` (e.g. `pqforge 0.4.6`, `pqforge keygen`), `profile` (pqforge profile name), `createdBy` (app-supplied, ≤ 128 UTF-8 bytes). |
| `rotatedFrom` | `KeyId?` | Now validated: must differ from `id`, and must resolve to an existing record. |
| `rotationOf` replaced by | `supersededBy` | `KeyId?` — the forward pointer, set on the predecessor by `rotate`. |
| `wrapPolicy` | `Map<String, String>` | Which protection the record is *supposed* to have: `provider` (`pqforge`/`platform`), `kdf`, `accessibility`, `requireUserPresence`. Advisory metadata — enforcement is the provider's job — but it makes "what was this stored as, and has that changed?" answerable without decrypting anything. |
| `retirePolicy` | `enum` | `retain` \| `tombstone` \| `delete` — what happens to a rotated-out key. `retain` is the default. |

`KeyMetadata` gets `const` constructors for each, `fromJson` gains a `version`
switch, and an unknown `version` in stored JSON is `FormatError`, never
`PolicyError` — a record from the future is a format problem.

### 2.3 `rotate`

```dart
Future<KsResult<KeyId>> rotate(
  KeyId oldId,
  KeyMetadata newMetadata,
  UnlockMethod unlock, {
  RetirePolicy retirePolicy = RetirePolicy.retain,
})
```

Semantics, and the reasoning for each:

1. `metadata(oldId)` must resolve; `NotFound` otherwise.
2. `newMetadata.id` must not already exist. `PolicyError` — never a silent
   overwrite (this is also §1.4's footgun closed).
3. `newMetadata.kind` and `.algorithm` must equal the old record's. Rotating
   X25519 into ML-KEM is not a rotation, it is a replacement; making the caller
   say so explicitly prevents an audit trail that lies.
4. **Read the old plaintext and write the new record.** This means `rotate`
   needs an unlock. There is no way around it that does not either re-key from
   outside (which exposes the secret) or store the plaintext (which is
   strictly worse). Document that plainly in the dartdoc: *rotation holds the
   key material in memory for the duration of the write*, and it is the one
   place in the facade where a secret outlives a single `use` callback.
5. The write goes through `put`, so the canonical AAD, the algorithm registry
   validation and the wipe discipline all apply unchanged. No second path.
6. On success: set `rotatedFrom` on the new metadata, and set
   `supersededBy = newMetadata.id` on the old record. **Both writes are part of
   the operation.** A rotation whose forward pointer failed to persist is worse
   than one that did not happen, because the lineage silently lies.
7. Apply `retirePolicy` to the predecessor.
8. The plaintext buffer is wiped in a `finally` per rule 10, on success, on
   `PolicyError`, and on any exception.

**Failure atomicity.** Steps 3–6 are not atomic across two file writes on a
POSIX filesystem, and pretending otherwise would be a false claim. Instead:

- The new record is written **first**. If anything fails, the old record is
  untouched and still readable — a rotation either did not happen or is
  complete.
- The predecessor's `supersededBy` update is a single additional write. If it
  fails, `rotate` returns `KsFailure(PlatformError(STORAGE_ERROR))` and the
  caller is told the forward pointer may be missing; the new record exists and
  is readable. This is stated in the dartdoc and in the release notes.
- Nothing here is claimed to be crash-atomic. Crash-recovery for a half-applied
  rotation is explicitly out of scope; see §6.

### 2.4 `rewrap`

```dart
/// Change the passphrase protecting a record without changing the key.
///
/// [newUnlock] replaces the protection; the key bytes are identical before and
/// after, and the old passphrase stops working the moment the write completes.
/// Non-atomic in exactly the same way as [rotate]: the new record is written
/// first, so a failure leaves the old record readable and unchanged.
///
/// This is the supported path for handling a suspected passphrase compromise,
/// and it is the reason a rotation is not the right answer to one — rotation
/// changes the key, rewrap does not, and rewrap is what an incident response
/// actually needs.
Future<KsResult<void>> rewrap(KeyId id, UnlockMethod newUnlock);
```

Implementation is the read-write-write shape of §2.3 with no metadata change
except `wrapPolicy`. The old passphrase is required as the current unlock; the
new one is the write's unlock.

Because `PqForgeKeystoreCrypto` derives a fresh Argon2id salt per wrap, the
ciphertext changes completely even though the plaintext does not. That is
expected, and a test asserts exactly that: same plaintext, different ciphertext,
different salt, old passphrase rejected, new passphrase accepted.

### 2.5 Lineage queries

```dart
/// Every key in [id]'s rotation chain, oldest first.
///
/// Walks `rotatedFrom` to the root and `supersededBy` towards the head. A
/// malformed chain — a cycle, a dangling pointer — yields `KsFailure(FormatError)`
/// naming the offending ID. It does not loop forever and it does not silently
/// stop early.
Future<KsResult<List<KeyId>>> lineage(KeyId id);

/// Keys that depend on [id] as their predecessor.
Future<KsResult<List<KeyId>>> rotatedTo(KeyId id);

/// The keys currently marked [RetirePolicy.tombstone] but not yet reaped.
Future<KsResult<List<KeyId>>> pendingReap();
```

Cycle detection is required. `rotatedFrom` is attacker-writable by anyone who
can write into the store directory, and an unguarded walk is an unbounded loop.

### 2.6 Explicit write modes

```dart
enum WriteMode {
  /// Overwrite any existing record. The default, preserving current behaviour.
  overwrite,

  /// Fail with `PolicyError` if the ID exists.
  createOnly,

  /// Fail with `NotFound` if the ID does not exist.
  replaceExisting,
}
```

`put` gains `{WriteMode mode = WriteMode.overwrite}`. `createOnly` is a
compare-then-write and is **not** atomic; the file store's per-directory lock
makes it atomic there and only there. That difference is documented on the enum
member rather than glossed over.

### 2.7 The `delete` contract, written down

`doc/FORMATS.md` gains a section stating, per platform, what `delete` removes and
what it leaves:

| Backend | Removed | Left behind |
| --- | --- | --- |
| Memory | map entry | nothing |
| File | the `.pqks` file | a `.deleted` tombstone **only** under `FallbackKeystoreBackend` |
| Android | PQNA file | nothing; the AndroidKeyStore alias is not erasable and its key material is destroyed with the app's keystore on uninstall |
| Darwin | keychain item | nothing; keychain items may survive an app uninstall depending on the access group |
| Windows | the PQNW file | nothing; DPAPI blobs are readable while the user profile exists |
| Linux | the Secret Service item | nothing |

And one honest API consequence: `use()` on a deleted key returns `NotFound`,
indistinguishable from a key that never existed. That is correct — distinguishing
them would leak existence — and it must be stated, not worked around.

---

## 3. Change list

- **L-1** `lib/src/api/key_metadata.dart`: v2 fields, `const` constructors,
  `fromJson` version switch, `RetirePolicy` enum, `toJson(v: 2)`. `fromJson`
  must tolerate a v1 document (all v2 keys absent).
- **L-2** `lib/src/crypto/canonical_aad.dart`: version parameter; v1 path
  unchanged, v2 path new. `test/canonical_aad_test.dart` golden vectors
  untouched — if they need regenerating, the implementation is wrong.
- **L-3** `lib/src/api/key_algorithm.dart` integration: `KeyMetadata`
  construction validated in `put` (`B-3`'s checks, now version-aware).
- **L-4** `PqForgeKeystoreCrypto.wrap`/`unwrap`: use `algorithm.pqforgeKeyKind`
  and `algorithm.id` instead of the constants; `unwrap` cross-checks the stored
  `algorithmId` against the metadata before the KDF runs (`B-4`).
- **L-5** `lib/src/api/key_import.dart` and the `metadataFor*` factories
  (`B-5`).
- **L-6** `PqKeystore.rotate`, `.rewrap`, `.lineage`, `.rotatedTo`,
  `.pendingReap`, `WriteMode`. `metadata()` gains `supersededBy`.
- **L-7** KeyKind renames under the v2 migration (`B-6`).
- **L-8** `FileKeystoreBackend`: predecessor-pointer write, tombstone creation
  for `retirePolicy: tombstone`, `delete` semantics per §2.7.
- **L-9** `FallbackKeystoreBackend`: honour `createOnly` (it owns tombstones, so
  it can answer "was this ever here?" where the file backend cannot).
- **L-10** `doc/FORMATS.md`: metadata v2 field table, the delete contract, the
  PQKS v1/v2 reading rule. `doc/API.md`: every new signature with its error
  table.

## 4. Test plan

### 4.1 Rotation

| Test | File | Assertion |
| --- | --- | --- |
| Happy path | `test/key_lifecycle_test.dart` | `rotate` → new record readable, plaintext byte-identical to the original, `rotatedFrom` set, predecessor's `supersededBy` set. |
| Kind/algorithm drift refused | same | `rotate` X25519 → ML-KEM → `PolicyError`, and the old record is still readable and unchanged. |
| Existing target refused | same | `rotate` onto an occupied ID → `PolicyError` (§2.3 step 2). |
| Predecessor unreadable after write | same | Read the old ID **inside a test hook that fails deliberately** so the old buffer is captured: assert it is all-zero. Rule 10 evidence for the new path. Verify by temporarily removing the wipe and confirming the test fails. |
| Retire policies | same | `retain` → old readable; `tombstone` → old returns `NotFound` and a tombstone exists; `delete` → old returns `NotFound` and no tombstone. |
| Forward pointer failure is reported | same | Backend stub whose second write throws → `KsFailure(PlatformError(STORAGE_ERROR))`, **new record still readable**, old record still readable. Asserts §2.3's non-atomicity is surfaced, not hidden. |
| Buffer wiped on every path | same | Assert the captured plaintext is all-zero after a `PolicyError` at step 3, after a backend throw at step 6, and after success. Three separate tests — one `finally` bug hides behind the other two. |

### 4.2 Rewrap

- Plaintext identical before and after; ciphertext, salt and nonce all different.
- Old passphrase → `CryptoError`; new passphrase → success.
- `wrapPolicy` updated; nothing else in the metadata changed.
- Captured plaintext all-zero after success and after a mid-write backend throw.

### 4.3 Lineage

- Linear chain of five keys, oldest first, no cycles.
- Dangling `rotatedFrom` → `FormatError` naming the ID; no infinite loop. Test
  with a **timeout** so a regression fails as a hang rather than passing.
- **Cycle**: `a.rotatedFrom = b`, `b.rotatedFrom = a` → `FormatError`. This is
  the security-relevant case: the input is attacker-writable.
- `rotatedTo`, `pendingReap` agree with `lineage`.

### 4.4 Schema and AAD compatibility

- A v1 golden metadata document loads through `fromJson`, all v2 fields null, and
  re-encodes to the **same** v1 AAD bytes.
- A v1 record written before 0.3.0 reads back correctly through the new code:
  `use()` succeeds, unwrap is invoked. This is the single most important
  backwards-compatibility test in the release.
- Unknown `version: 3` in stored JSON → `FormatError`.
- `KeyKind` renames: a v1 record naming `classicalX25519` still decodes.

### 4.5 Write modes

- `createOnly` onto an existing ID → `PolicyError`, original intact.
- `replaceExisting` onto a missing ID → `NotFound`.
- `overwrite` remains the default and does not change any existing test.

## 5. Exit gate

Rotation and re-wrap round-trip through every backend, with tests asserting the
predecessor's fate in each case. Plus, specifically:

- Every v1 record written before this release still reads.
- `canonicalAad` v1 output is byte-identical, proven by unmodified golden
  vectors.
- Every new plaintext path has a rule-10 regression test that fails when the
  wipe is removed.
- Rotation's non-atomicity is documented, and the failure mode is tested rather
  than assumed.

## 6. Non-goals

- **No claim that `rotate` is crash-atomic.** It is not, and §2.3 says so in the
  dartdoc. Journaling or a write-ahead intent record is a 0.4.0 question at
  best.
- **No key-change-history audit log.** `lineage` reconstructs from metadata; it
  is not a tamper-evident log and must not be described as one.
- **No cross-device export.** That is [`040-backup-restore-migration.md`](040-backup-restore-migration.md).
- **No re-keying.** `rotate` copies the same bytes. Changing what the key *is*
  belongs to `pqforge`'s generator, not to a custody layer.
- **No claim that `delete` erases material.** See §2.7's table — DPAPI blobs
  outlive the file, keychain items may outlive the app, and an
  AndroidKeyStore alias outlives the `.pqna` file until uninstall.
- **No metadata-at-rest confidentiality.** PQKS stores metadata in cleartext,
  bound by the AAD but readable. `provenance` and `wrapPolicy` add to that. That
  is a documented property, not a regression, and it belongs in
  [`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md) as an explicit statement rather
  than being quietly relied upon not to matter.