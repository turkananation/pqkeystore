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
| [`ROADMAP.md`](ROADMAP.md) | Project phases and release planning. |

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
