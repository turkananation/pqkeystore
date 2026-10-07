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

## Proposed Resolution (2026-10-07)

Contract v1 is specified in [`PLATFORM_CONTRACT.md`](../PLATFORM_CONTRACT.md) and implemented on all five platforms; per-platform choices are in [ADR-0009](0009-native-backend-designs.md). The status stays **Proposed** until maintainers accept it and every platform CI job passes.

- **Argument names:** `id`, `data`, `options`. Argument maps are closed (unknown keys → `INVALID_ARGS`).
- **Not-found:** `get` → `null`, `contains`/`delete` → `false`. No `NOT_FOUND` error code.
- **Metadata:** no separate metadata operations. Native code stores only the PQKS blob, and Dart filters `list()` by decoding records. This makes each write one atomic native operation and removes the `__meta__` namespace (BUG-010). `putJson`/`getJson` are removed.
- **Options:** all four keys are required. Each non-default value is a capability request that is either enforced or rejected with `UNSUPPORTED_OPTION`, according to `platformInfo.supportedOptions` evaluated at call time. `accessibleWhenUnlocked: bool` is replaced by `accessibility: platformDefault | whenUnlocked | afterFirstUnlock`, so the defaults are portable.
- **Versioning:** `platformInfo.contractVersion` is checked by a one-time client handshake.
- **Errors:** a closed set of nine native codes plus the Dart-only `CONTRACT_MISMATCH`.
- **Shared tests:** `test/contract/platform_contract_suite.dart` runs against a pure-Dart reference (`flutter test`) and against each native implementation (`example/integration_test/`).
