# Changelog

## Unreleased

* **Documented every public type.** All 20 previously-undocumented top-level
  declarations now carry dartdoc: the `PqKeystoreError` hierarchy and `KsResult`,
  `KeyId`, `KeyKind`, `UnlockMethod` and its three subclasses, `ThresholdMeta`,
  `KeyMetadata`, `SealedRecord`, `BackendType` and `createBackend`.
  API-document coverage measured against the whole `lib/` tree goes from 16.3%
  to 30.3% (pub.dev scores the `>= 20%` band).
  The docs state the things a caller can otherwise get wrong: that metadata is
  stored in cleartext and must not hold secrets; that a record's metadata cannot
  be edited in place without rewriting the record; that `PlatformUnlock` and
  `PassphraseThenPlatform` are refused in format version 1; that `NotFound` is
  deliberately indistinguishable from "deleted".
* **`dart format` applied to `lib/` and `test/`.** Eight files were not
  formatter-clean on `main`, which costs pub points.

* **Breaking:** Platform channel contract v1 (`doc/PLATFORM_CONTRACT.md`):
  - Removed `putJson`/`getJson` and the `__meta__` metadata sidecar. `list()` filters on decoded PQKS metadata, and `__meta__`-prefixed IDs are now ordinary IDs (BUG-010).
  - Arguments are `id`/`data`/`options`; `delete` returns a bool; `listIds` is implemented on every platform (BUG-002/003/004).
  - `PlatformStoreOptions.accessibleWhenUnlocked` is replaced by `accessibility: PlatformAccessibility`. Unsupported options fail with `UNSUPPORTED_OPTION`.
  - Added `PlatformContract`, `PlatformErrorCode`, `PlatformInfo`, `PlatformKeystoreBackend.platformInfo()` and `.listIds()`. Records are bound to their storage ID on read.
* Native backends: Android (AndroidKeyStore + noBackup files, PQNA v2 envelope), iOS/macOS (shared `darwin/` source, data protection keychain, CocoaPods + SwiftPM, privacy manifest), Windows (DPAPI files, PQNW envelope), Linux (libsecret, no file fallback, bounded reachability probe).
* `PQNA` v2 seals records as 48 KiB chunks (nChunks-prefixed IV blob, one AEAD tag per chunk), fixing AndroidKeyStore GCM tag failures on API ≤28 for large records. On-device instrumentation test (`OnDeviceRoundTripTest`) added; PQNA v1 (the pre-chunk layout) is rejected on read.
* `FileKeystoreBackend` rewritten as file store v1: hashed filenames, no untrusted index, strict record framing, atomic replace, verified permissions. Legacy sanitized-name directories are adopted in place.
* **Breaking (behavioural):** `PqKeystore.use` now re-validates every record before calling the crypto adapter — the decoded metadata ID must equal the requested ID and the stored AAD must equal the canonical AAD recomputed from that metadata. A mismatch returns `FormatError` (`PqKeystoreError`) and `unwrap` is never invoked. Callers that relied on reading back a record whose metadata or AAD had been edited out of band now get a failure instead of plaintext (BUG-005, ADR-0006).
* Added `test/record_invariants_test.dart` covering per-field metadata tampering with a preserved AAD, record-identity mismatches, and PQKS framing (trailing bytes, truncation, absurd field lengths, unsupported version).
* **Security fix:** `PqKeystore.use` now wipes the buffer returned by `PqKeystoreCrypto.unwrap`. `SecretBytes.fromUint8List` always copies and never takes ownership, so the previous code disposed the copy and left the original plaintext live in the heap until the garbage collector reclaimed it — readable from swap, core dumps and post-mortem debugging. The source buffer is now zeroed with `secureZero` immediately after the copy (inside a `finally`, so it is cleared even if the copy throws), and the callback copy is wiped with `secureZero` instead of a hand-written loop, which survives Dead Store Elimination in AOT builds. Covered by `test/secret_lifetime_test.dart`. This is now [AGENTS.md rule 10](AGENTS.md).
* Removed the temporary `NSLog` diagnostics from the Darwin `listIds` implementation that were committed during the keychain-account investigation.
* `FallbackKeystoreBackend`: opt-in dual-read/migrate-on-write file fallback with tombstone replay, triggered only on `UNAVAILABLE` (ADR-0010).
* `doc/FORMATS.md` is the single reference for on-disk layouts (PQKS, PQNA, PQNW, file store v1, tombstones).
* Shared contract suite (pure-Dart reference + on-device `integration_test`), native unit tests, five-platform CI workflow.
* Example app runners for all five platforms; the example is now a real package consumer.

## 0.1.0-dev.1

* Initial scaffold of the `pqkeystore` package.
* Added root configuration files (pubspec, analysis_options, gitignore, LICENSE).
* Added SECURITY.md outlining defense-in-depth model and reporting guidelines.
