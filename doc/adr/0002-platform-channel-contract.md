# ADR-0002: Platform Channel Contract

- Status: Proposed
- Date: 2026-10-04

## Context

The Dart backend currently sends `id` and `data`; existing Android and Apple handlers expect `key` and `value`. Dart also expects a boolean delete result and calls `listIds`, which current handlers do not consistently provide. Options and errors are not implemented uniformly.

## Decision

Define and test one versioned contract before changing native implementations. The contract must specify the frozen channel name, each method's exact argument and result types, missing-item behavior, error codes, list ordering/contents, metadata operations, and option handling. The current Dart key names (`id` and `data`) are the proposed canonical names, subject to review against native conventions.

Required operations include put, get, delete, contains, listIds, putJson, getJson, and platformInfo. Delete must have one explicit success/not-found contract. Every platform must reject unknown or unsupported options consistently rather than silently ignoring security-related settings.

## Consequences

- Add contract tests reusable across all five native implementations.
- Do not treat the existing Dart or native argument names as authoritative until this ADR is accepted and tests encode the choice.
- Keep the channel name `com.yardenah.pqkeystore/store` on every platform.

## Alternatives Considered

- Change only the Dart side to match each native implementation. Rejected because platform drift would remain likely.
- Allow per-platform schemas. Rejected because it defeats parity and increases caller-visible behavioral differences.

## Open Questions

- Should not-found be represented as `null`/`false` or a standardized platform error for each operation?
- Should metadata index operations remain separate channel calls or be part of an atomic record operation?
- Which option fields are required for v1 on each OS?
