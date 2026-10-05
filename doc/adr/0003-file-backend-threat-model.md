# ADR-0003: File Backend Threat Model And Durability

- Status: Proposed
- Date: 2026-10-04

## Context

The file backend maps IDs through sanitization that can collide, removes an existing record before replacement is safely committed, and maintains an index with an unkeyed checksum. The checksum can detect some accidental corruption but cannot authenticate the index against an attacker able to edit it. Index entries also contain caller-controlled path strings; `contains` and `list` use those paths without proving they remain under the configured directory. Concurrent writers have no declared serialization contract.

## Decision

Before calling the file backend production-capable, explicitly choose its attacker model and document that boundary. Regardless of that choice, ID-to-path mapping must be collision-safe; persisted index data must never select files outside the configured root; replacement must preserve the previous valid record until the new record is committed; and decoded record identity must match the requested storage identity. Define behavior for concurrent operations in one process and across processes, including recovery after a crash between record and index updates.

Treat the current unkeyed checksum as corruption detection only. Do not describe it as a cryptographic seal or adversarial tamper protection. A keyed index-authentication design requires a separately approved key lifecycle and is not assumed by this ADR.

## Consequences

- Add collision, interruption, malformed-index, and identity-mismatch tests.
- State filesystem permission and backup expectations by platform.
- If the accepted threat model requires authenticated index integrity, the backend remains blocked until a key-management design is approved.

## Alternatives Considered

- Keep sanitized names and document collision as caller responsibility. Rejected because valid IDs can silently alias.
- Claim the checksum authenticates the index. Rejected because it is unkeyed and recomputable by an editor.
- Remove the old record before writing the replacement. Rejected because a failed update can destroy valid state.

## Open Questions

- Is the file backend intended for production desktop use or only development/testing?
- Is an attacker who can modify application storage in scope for file-backend integrity?
- Which portable atomic-replacement and filesystem-permission guarantees can each supported Dart runtime provide?
