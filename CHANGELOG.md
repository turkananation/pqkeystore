# Changelog

## Unreleased

* **Breaking:** Platform channel contract v1 (`doc/PLATFORM_CONTRACT.md`):
  - Removed `putJson`/`getJson` and the `__meta__` metadata sidecar. `list()` filters on decoded PQKS metadata, and `__meta__`-prefixed IDs are now ordinary IDs (BUG-010).
  - Arguments are `id`/`data`/`options`; `delete` returns a bool; `listIds` is implemented on every platform (BUG-002/003/004).
  - `PlatformStoreOptions.accessibleWhenUnlocked` is replaced by `accessibility: PlatformAccessibility`. Unsupported options fail with `UNSUPPORTED_OPTION`.
  - Added `PlatformContract`, `PlatformErrorCode`, `PlatformInfo`, `PlatformKeystoreBackend.platformInfo()` and `.listIds()`. Records are bound to their storage ID on read.
* Native backends: Android (AndroidKeyStore + noBackup files, PQNA envelope), iOS/macOS (shared `darwin/` source, data protection keychain, CocoaPods + SwiftPM, privacy manifest), Windows (DPAPI files, PQNW envelope), Linux (libsecret, no file fallback, bounded reachability probe).
* `FileKeystoreBackend` rewritten as file store v1: hashed filenames, no untrusted index, strict record framing, atomic replace, verified permissions. Legacy sanitized-name directories are adopted in place.
* `FallbackKeystoreBackend`: opt-in dual-read/migrate-on-write file fallback with tombstone replay, triggered only on `UNAVAILABLE` (ADR-0010).
* `doc/FORMATS.md` is the single reference for on-disk layouts (PQKS, PQNA, PQNW, file store v1, tombstones).
* Shared contract suite (pure-Dart reference + on-device `integration_test`), native unit tests, five-platform CI workflow.
* Example app runners for all five platforms; the example is now a real package consumer.

## 0.1.0-dev.1

* Initial scaffold of the `pqkeystore` package.
* Added root configuration files (pubspec, analysis_options, gitignore, LICENSE).
* Added SECURITY.md outlining defense-in-depth model and reporting guidelines.
