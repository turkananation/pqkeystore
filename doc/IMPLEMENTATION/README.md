# Implementation series — 0.2.0 to 0.4.0

Four documents that, taken together, are enough to implement `0.2.0`, `0.3.0`
and `0.4.0` without re-deriving a single design decision.

| Document | Covers | Lands in |
| --- | --- | --- |
| [`CROSS-CUTTING.md`](CROSS-CUTTING.md) | `StubKeystoreCrypto` removal, first-class key provenance (pqforge / pqcrypto / pqdga / pqthreshold), modern Dart and isolate policy | 0.2.0 (blocking) |
| [`020-platform-unlock.md`](020-platform-unlock.md) | Per-write options, real `PlatformUnlock`, chained `PassphraseThenPlatform`, capability negotiation, Android user presence | 0.2.0 |
| [`030-key-lifecycle.md`](030-key-lifecycle.md) | `rotate`, `rewrap`, lineage queries, metadata v2 and its migration | 0.3.0 |
| [`040-backup-restore-migration.md`](040-backup-restore-migration.md) | Backup/restore protocol, store inspection, PQKS format migration | 0.4.0 |

## How to use these documents

Each document has the same six sections, in the same order:

1. **Current state** — what the code does today, with `file:line` references.
   If a cited line no longer matches, the document is stale: fix it, do not
   guess.
2. **Target state** — the API and byte formats after the change, complete
   enough to transcribe. Type signatures, error names, and wire keys are all
   final wording.
3. **Change list** — an ordered, file-by-file task list. Each task names the
   file, the symbol, and what "done" looks like. Tasks are ordered so that no
   task depends on a later one.
4. **Test plan** — every test named by file and by assertion, including the
   negative cases. A task is not finished until its tests exist.
5. **Exit gate** — the literal acceptance bar, copied from
   [`../ROADMAP.md`](../ROADMAP.md) so it cannot drift.
6. **Non-goals** — what is deliberately *not* done, and what must not be
   claimed when it is done.

## Rules that apply to all of them

- [`AGENTS.md`](../../AGENTS.md) is binding, especially rule 5 (claim boundary
  first) and rule 10 (every plaintext buffer wiped).
- Security properties are recorded in [`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md)
  **before** the code that implements them lands. A property with no claim
  entry does not get one retroactively "because we implemented it".
- Every new platform behaviour goes through the shared conformance suite in
  [`../../test/contract/platform_contract_suite.dart`](../../test/contract/platform_contract_suite.dart)
  on all five targets. Native code that is not reachable from the suite is
  native code nobody has tested.
- `publish_to: 'none'` stays until [`../ROADMAP.md`](../ROADMAP.md) § *0.1.0
  exit criterion* is satisfied.

## Verification baseline these plans were written against

`main` at `f202d75`: 135 passing tests, `dart analyze` clean, CI run
37770096113 green on Dart, Linux, Windows, Android (API 26/28/35) and iOS
(SwiftPM). macOS and iOS CocoaPods fail fast by design for want of an Apple
signing identity.