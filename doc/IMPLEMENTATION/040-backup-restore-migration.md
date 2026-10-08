# 0.4.0 — Backup, restore and migration

Making records outlive one device, plus a supported format-migration path. The
theme: `pqkeystore` is a custody layer, and custody that cannot be moved, and
cannot be upgraded, is a single point of failure.

---

## 1. Current state

### 1.1 Portability is uneven and undocumented as a policy

[`../FORMATS.md`](../FORMATS.md) states which formats are portable, and the
table is already honest: PQKS is portable, and PQNA (Android), PQNW (Windows),
the Darwin keychain item and the Secret Service item are all device-bound. But
nothing in the public API exposes that distinction. An application cannot ask
"can I move this record to another device?", and there is no backup operation at
all.

The consequence is the failure users actually hit: an app that used the platform
backend everywhere loses every key on device loss, discovers this during
recovery, and has no tooling.

### 1.2 Exporting bytes is possible but nobody does it safely

`put` accepts arbitrary bytes, so a caller *can* read a record with `use()` and
write it somewhere themselves. Doing so means the plaintext exists in
application code and in an unbounded file, with no integrity binding between the
exported bytes and the record they came from, and no way to validate a
re-import. There is no manifest, so a partial backup cannot be distinguished
from a complete one.

### 1.3 There is no version negotiation on read

`SealedRecord` carries `version` (`u32`, currently `1`) and the decoder rejects
unknown versions. That is correct and it is the whole of the migration story: a
v2 record makes an old build fail closed. There is no way to *produce* a v2
record yet, and no documented policy for what happens when a store contains a
mix.

### 1.4 The legacy-adoption path is unreusable outside itself

`FileKeystoreBackend` already performs exactly the checks a store inspector
needs — name is `hex(SHA-256(ID))`, ID is read back from the record and
cross-checked, permissions verified, stale temps reclaimed, ad-hoc names
adopted. That logic is entangled with the write path and is not callable as a
standalone validator.

---

## 2. Target state

### 2.1 Portability is a first-class, queryable property

```dart
/// Whether a record can move to another device, and what a move requires.
final class PortabilityPolicy {
  const PortabilityPolicy({
    required this.portable,
    required this.requiresReEnrollment,
    required this.notes,
  });

  /// True when the record's bytes are self-contained: PQKS with a
  /// passphrase-derived protection, or a `pqforge`-wrapped blob stored as
  /// `opaque/v1`.
  final bool portable;

  /// True when restoring on a new device produces a record that is *not*
  /// equivalent to the original — e.g. an AndroidKeyStore- or DPAPI-bound record
  /// must be re-sealed under the new device's key before it can be read.
  final bool requiresReEnrollment;

  /// Human-readable, per-platform. Documentation, not machine-readable.
  final String notes;
}

Future<KsResult<PortabilityPolicy>> portability(KeyId id);
```

Backed by the provider, not guessed:

| Protection | portable | requiresReEnrollment | notes |
| --- | --- | --- | --- |
| `pqforge-argon2id-aes-256-gcm-v1` | yes | no | Same passphrase on the new device. |
| `platform-os-unlock/v1` (Apple) | **yes**, via synchronizable items only | no | Only when written with `synchronizable: true`; requires an iCloud Keychain entitlement the app must already hold. |
| `platform-os-unlock/v1` (Android, DPAPI, Secret Service) | no | yes | The OS binding is to the old device. Re-sealing is required. |

`requiresReEnrollment` is the honest one: exporting an AndroidKeyStore-bound
record produces ciphertext the new device cannot decrypt. Exporting it anyway
produces a file that fails with `KEY_INVALIDATED` or `CryptoError` at restore
time, and the documentation must say that before a user discovers it.

### 2.2 Backup: `PQBA` archive

New format, documented in [`../FORMATS.md`](../FORMATS.md) § *Backup archive*
before any code writes one.

```
 0  "PQBA"                                  magic (4)
 4  formatVersion                            u32, currently 1
 8  flags                                   u32, bitfield, reserved bits must be 0
12  manifestLength                          u32
    manifest JSON                           UTF-8, canonical JSON, see below
    headerLength                            u32
    header bytes                            pqforge PqStreamingHeader, PQFS, verbatim
    record count                            u32
    record entries                          recordCount × (see below)
```

Each record entry:

```
    id length                               u32
    id bytes                                UTF-8, validated by validatePlatformKeyId
    offset                                  u64, from the start of the file
    length                                  u32, ≤ PlatformContract.maxRecordBytes
    content kind                            u8: 0 = raw PQKS record, 1 = opaque blob
    sha256 of the entry bytes               32
```

**Manifest fields:** `createdAt` (UTC ISO-8601), `tool` (`pqkeystore <version>`),
`source` (`os` + optional `hostApp`), `recordCount`, and a `records[]` array of
`{id, kind, algorithm, length, sha256}` — the same identity fields the record
carries, so a restore can pre-validate the whole archive against the manifest
before decrypting anything.

**The payload is one pqforge `PQFS` streaming envelope** containing every
selected record, concatenated. `PqStreamingHeader.defaultFrameSize` is 1 MiB
(`1 << 20`) and `maxFrameSize` is 64 MiB, so the archive header is copied
verbatim from `pqforge`'s streaming envelope rather than reinvented — that is
the point of using it: chunked AEAD framing, per-frame nonces, and a header that
already carries the KEM and profile.

Which KEM seals the archive is a **caller decision**, not a `pqkeystore` one:

- `PqForge.generateKeys(...)` for a fresh recipient keypair, or
- `PqForge.hybridEncapsulate(...)` for a hybrid classical+PQ recipient.

`pqkeystore` selects and orchestrates; it never generates a sealing key for the
caller (rule 3). The chosen `PqKeyBundle` is recorded in the manifest so restore
knows what it needs.

**Plaintext never reaches the filesystem in backup form.** Each record is added
to the streaming envelope from the buffer `use()` hands over; the archive's
frames are what get written. This is a real property and it is worth a test:
the on-disk archive must not contain a record's plaintext, even for a record
whose `wrapAlg` is itself passphrase-based. The archive is encrypted once, by
the KEM, and the per-record protection stays *inside* the envelope — a backup is
never downgraded to "just an encrypted blob".

### 2.3 API

```dart
/// Write an encrypted archive of [ids] to [path].
///
/// The archive is sealed to [recipient]'s public key. [path] is created with
/// mode 0600 in a 0700 parent, written to a temporary file, fsynced, and
/// atomically renamed — the same sequence [FileKeystoreBackend] already uses,
/// because a half-written backup is worse than no backup.
///
/// Returns the archive's SHA-256 so the caller can record it. Returns
/// `KsFailure(PolicyError)` for a non-portable id unless [allowDeviceBound] is
/// set, in which case the id is included and the archive records
/// `requiresReEnrollment: true` for it.
Future<KsResult<String>> backup(
  Iterable<KeyId> ids,
  String path,
  PqKeyBundle recipient, {
  bool allowDeviceBound = false,
});

/// Validate and decrypt an archive without writing anything.
///
/// This is the dry run: it checks the magic, the framing, every length, every
/// manifest hash and every id, and reports what a restore *would* do. No record
/// is written. Callers should run it before `restore`, and the release example
/// should.
Future<KsResult<BackupPlan>> inspectBackup(String path);

/// Restore [id] from an archive verified by [inspectBackup].
///
/// Rejects any record whose bytes do not match the manifest hash, or whose
/// identity fails the canonical AAD check. Writes go through the same
/// [WriteMode] and algorithm-registry validation as [PqKeystore.put].
Future<KsResult<void>> restore(
  String path,
  KeyId id,
  UnlockMethod unlock, {
  WriteMode mode = WriteMode.createOnly,
  String? rewrapPassphrase,
});
```

`WriteMode.createOnly` is the **default** for restore, unlike `put`. A restore
that silently overwrites a live key because an ID collided is a data-loss bug
wearing a helpful hat.

`BackupPlan` reports: format version, record count, per-record
`{id, kind, algorithm, portable, requiresReEnrollment}`, and any problems found
without throwing.

`rewrapPassphrase` exists for the device-bound case: the record arrives
protected by the *old* device's OS binding, which cannot be satisfied. Restore
therefore requires a **new** passphrase, writes a record protected from the start
by `rewrapPassphrase`, and records the re-enrollment in `provenance`. The old
device's binding is discarded, not migrated.

### 2.4 Store inspection

Extract `FileKeystoreBackend`'s existing validation into a reusable scanner:

```dart
/// The result of scanning a store directory.
final class StoreInspection {
  const StoreInspection({
    required this.valid,
    required this.adoptable,
    required this.orphaned,
    required this.staleTemporaries,
    required this.permissionProblems,
  });

  final List<KeyId> valid;
  final List<String> adoptable;      // non-hash names that decode cleanly
  final List<KeyId> orphaned;        // name↔record mismatch: a correctness bug
  final List<String> staleTemporaries;
  final List<String> permissionProblems;
}

/// Scan [directory] without modifying it.
Future<KsResult<StoreInspection>> inspectStore(String directory);
```

- Purely read-only. It reports, it does not repair.
- `adoptable` is reported, never adopted implicitly; adoption stays an explicit
  `adoptLegacyNames()` call, because silently renaming files during an audit is
  the wrong default.
- `orphaned` is the dangerous bucket — a file whose name hash does not match its
  embedded ID. `inspectStore` reports it; [`../FORMATS.md`](../FORMATS.md) § 2
  says such a file is not an entry, and this is where an operator finds out.

### 2.5 Format migration

Migration is a *read-old, write-new* operation, never an in-place rewrite. In-place
rewrites have no rollback and turn a failed upgrade into data loss.

```dart
/// Rewrite [id] from PQKS v1 to the current format.
///
/// Reads with the v1 decoder, re-encodes as v2, writes to a new record, and only
/// then removes the original. On any failure the original is untouched.
///
/// [PqKS version] is a sealed hierarchy — `final class V1Record` and
/// `final class V2Record` — so adding a version is a compile error at every
/// unhandled site rather than a runtime surprise.
Future<KsResult<void>> migrate(KeyId id);
Future<KsResult<List<KeyId>>> migratable();
```

`migratable()` lists every record still on v1 — the operator's work list.

**Version negotiation on read:** the decoder accepts v1 and v2, rejects anything
else with `FormatError`. A record whose version is *newer* than this build's
must never be guessed at, and it must never be silently skipped in `migratable()`
— it is listed separately as "ahead of this build" so the report cannot imply the
store is fully understood.

`doc/FORMATS.md` documents both versions side by side with the exact byte
difference, and `CHANGELOG.md` states that v1 readers cannot read v2 records —
that is the whole point of failing closed.

---

## 3. Change list

- **B-1** `lib/src/backup/portability.dart` — `PortabilityPolicy`, `portability()`,
  backed by provider capability.
- **B-2** `lib/src/backup/archive_writer.dart` — PQBA framing, `PqStreamingHeader`
  copy, per-entry hashing, atomic temp+rename, 0600/0700.
- **B-3** `lib/src/backup/archive_reader.dart` — PQBA parse, manifest
  verification, entry hash verification, `inspectBackup`.
- **B-4** `lib/src/backup/plan.dart` — `BackupPlan`.
- **B-5** `PqKeystore.backup`, `.inspectBackup`, `.restore`. `restore` reuses the
  identity validation from `_validateRecordIdentity` and the registry checks from
  [`CROSS-CUTTING.md`](CROSS-CUTTING.md) `B-3` — no third path.
- **B-6** `lib/src/file_store/inspection.dart` — extract from
  `FileKeystoreBackend`, plus `adoptLegacyNames()` as a separate call.
- **B-7** `lib/src/api/record_version.dart` — sealed `V1Record`/`V2Record`,
  `migrate()`, `migratable()`.
- **B-8** `doc/FORMATS.md`: PQBA spec and PQKS v1/v2 side by side — **written
  first**.
- **B-9** Example app: backup → inspect → restore against a temp directory, with
  the manifest printed so the operator sees what was verified.

## 4. Test plan

### 4.1 Archive round trip

| Test | File | Assertion |
| --- | --- | --- |
| Round trip | `test/backup_test.dart` | Backup 3 records → inspect → restore all 3 → each `use()` returns byte-identical plaintext. |
| Manifest integrity | same | Flip one byte in the archive → `inspectBackup` fails naming the record and the offset; **no** record written. |
| Truncated archive | same | Truncate mid-frame → `FormatError`. Trailing garbage after the last frame → `FormatError` (the same strict framing rule as PQKS). |
| Entry offset lie | same | Corrupt an entry's recorded offset to point into another record's bytes → hash mismatch, `inspectBackup` fails, nothing written. |
| No plaintext on disk | same | Back up a passphrase-protected record, then scan the resulting file bytes for the record's plaintext → absent. This is the §2.2 claim; it gets its own test. |
| Permissions | same | Archive is 0600, parent 0700; on Windows assert the ACL equivalent is applied, or skip with a recorded reason — never pass silently. |
| Atomicity | same | Stub the writer to throw after N bytes → no partial file at `path`; the temp file is reclaimed. |
| `createOnly` default | same | Restore onto an existing ID → `PolicyError`, existing record untouched. |
| Device-bound refusal | same | Android/Darwin/Windows/Linux provider fakes: `backup` of a device-bound record without `allowDeviceBound` → `PolicyError`; with it, the manifest records `requiresReEnrollment`. |
| Re-enrollment on restore | same | Restoring a device-bound record with `rewrapPassphrase` → readable with the new passphrase, old binding gone, `provenance` records it. |

### 4.2 Empty and edge cases

- Empty `ids` → a valid archive with `recordCount: 0`. Not an error.
- 1 record, 1 MiB record (the contract maximum) — the streaming envelope's
  frame size boundary. Assert frame count and that no single frame exceeds
  `maxFrameSize`.
- Duplicate ID in `ids` → deduplicated once, not written twice.

### 4.3 Store inspection

- Clean store → all `valid`, everything else empty.
- Ad-hoc-named but decodable → `adoptable`, and `inspectStore` does **not**
  rename; `adoptLegacyNames()` does.
- Name hash ≠ embedded ID → `orphaned`, never `valid`.
- Stale temp file → `staleTemporaries`.
- `0700`/`0600` violated → `permissionProblems`.
- Read-only: assert the directory mtime and listing are unchanged after a scan.

### 4.4 Migration

- v1 record → `migrate()` → decodes as v2, `use()` succeeds, original removed.
- Failure mid-migrate → original still present and readable.
- `migratable()` lists v1 records and **separately** reports records ahead of the
  build.
- A v1 record read by v2-aware code produces the identical canonical AAD —
  unchanged golden vectors from 0.3.0.
- Unknown version → `FormatError`, never a guess.

## 5. Exit gate

Copied from [`../ROADMAP.md`](../ROADMAP.md) § *0.4.0*: restore on a clean
device is documented and tested per platform class; unsupported combinations fail
loudly. Plus:

- No restore path writes anything before the archive is fully verified.
- `createOnly` is the restore default.
- Every byte `doc/FORMATS.md` specifies is produced by a test, and every byte it
  specifies is parsed by a test.

## 6. Non-goals

- **No cross-vendor key portability claim.** A backup restores the *record*; the
  key inside it is still an ML-KEM or an X25519 key, and nothing here makes any
  algorithm more portable than it is.
- **No silent automatic migration.** `migratable()` reports; `migrate()` acts;
  nothing runs on its own at startup.
- **No backup of device-bound records that pretends to work.** They are refused
  by default and marked `requiresReEnrollment` when explicitly allowed.
- **No claim that a backup is tamper-evident.** The manifest hashes are
  *integrity against corruption and truncation*. An attacker who can rewrite the
  whole archive rewrites the manifest too. Saying "verified manifest" without
  that qualifier would be a false claim; the dartdoc must carry the qualifier.
- **No iCloud/Keychain sync orchestration.** `synchronizable` is an option the
  OS honours; `pqkeystore` does not manage the entitlement or the iCloud state,
  and does not claim it survives a keychain reset.
- **No streaming restore of an archive larger than available memory.** The
  streaming envelope handles the *encryption* framing; the reader still needs the
  record in memory to validate it, and the 1 MiB per-record cap is unchanged.