# Documentation Index

Architecture, API, platform behaviour and security claims for `pqkeystore`.

## Start here

* [`../README.md`](../README.md) — what the package is, quick start, status.
* [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md) — **what is claimed, what is not, and the evidence for each.** Read this before relying on any security property.
* [`../AGENTS.md`](../AGENTS.md) — hard rules for contributors and agents.

## Reference

| Document | Contents |
| --- | --- |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Component layering and data flow. |
| [`API.md`](API.md) | Public classes, methods and data structures. |
| [`FORMATS.md`](FORMATS.md) | Every on-disk byte layout: PQKS, PQNA, PQNW, keychain item, Secret Service item, file store v1, tombstones. |
| [`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md) | Normative native channel contract v1. |
| [`PLATFORM.md`](PLATFORM.md) | Platform status matrix, enforceable options, integration requirements. |
| [`INTEGRATION.md`](INTEGRATION.md) | How `pqkeystore` fits into the Yardenah stack (`pqforge`, `zeroize`, …). |
| [`SECURITY.md`](SECURITY.md) | Threat model, trust boundaries, defense in depth. |
| [`ROADMAP.md`](ROADMAP.md) | The ten-version plan, 0.1.0 → 1.0.0. |

## Implementation plans

Detailed, ordered, test-by-test plans for the next three releases. Read these
before writing code for 0.2.0, 0.3.0 or 0.4.0 — each cites the current
`file:line` state it is planning against, so a stale line number means a stale
document.

| Document | Covers |
| --- | --- |
| [`IMPLEMENTATION/README.md`](IMPLEMENTATION/README.md) | Index and how to read the series. |
| [`IMPLEMENTATION/CROSS-CUTTING.md`](IMPLEMENTATION/CROSS-CUTTING.md) | `StubKeystoreCrypto` removal, first-class key provenance from `pqforge`/`pqcrypto`/`pqthreshold`/`pqdga`, modern Dart and isolate policy, KDF parameter bounds. |
| [`IMPLEMENTATION/020-platform-unlock.md`](IMPLEMENTATION/020-platform-unlock.md) | Per-write options, real `PlatformUnlock`, chained `PassphraseThenPlatform`, capability negotiation, Android user presence. |
| [`IMPLEMENTATION/030-key-lifecycle.md`](IMPLEMENTATION/030-key-lifecycle.md) | `rotate`, `rewrap`, lineage, metadata v2 and its migration, write modes, the `delete` contract. |
| [`IMPLEMENTATION/040-backup-restore-migration.md`](IMPLEMENTATION/040-backup-restore-migration.md) | Portability policy, the PQBA backup archive, store inspection, PQKS format migration. |

## Upstream dependencies

| Document | Contents |
| --- | --- |
| [`UPSTREAM.md`](UPSTREAM.md) | What `pqkeystore` needs from `pqforge`, `pqthreshold`, `pqcrypto`, `pqdga` and `zeroize`: verified facts, open work, blocked decisions, and defects found in our own merged docs. |

## Work tracking

| Document | Contents |
| --- | --- |
| [`TRACKER.md`](TRACKER.md) | Production-readiness items, dependencies, acceptance criteria, release gates. |
| [`BUGS.md`](BUGS.md) | Confirmed defects, their evidence and their verification criteria. |
| [`adr/`](adr/0001-five-platform-v1.md) | Architecture decision records (ADR-0001 … ADR-0010). |

## Per-platform implementation notes

Storage model, capabilities, error mapping, durability and explicit non-claims:

* [`../android/README.md`](../android/README.md) — AndroidKeyStore, PQNA v2, chunking, API 26+.
* [`../darwin/README.md`](../darwin/README.md) — iOS **and** macOS (shared source), keychain accounts, crash-safe replacement, signing.
* [`../windows/README.md`](../windows/README.md) — DPAPI, PQNW, atomic replace, isolation limits.
* [`../linux/README.md`](../linux/README.md) — Secret Service, no silent file fallback, provider limits.
