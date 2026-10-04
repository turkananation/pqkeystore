# ADR-0001: Five-Platform v1 Support

- Status: Accepted
- Date: 2026-10-04

## Context

Package metadata registers Android, iOS, macOS, Windows, and Linux, while the current Linux and Windows plugins are stubs and Android/Apple implementations are partial. The project requires an explicit support commitment rather than implying that registration equals working support.

## Decision

All five registered platforms are required for v1. A platform is supported only after it implements the common storage contract, builds in CI, and passes platform contract tests. A stub or merely registered plugin does not count as support.

## Consequences

- Windows and Linux implementations are release blockers, not optional follow-up work.
- Android, iOS, and macOS must also pass the same behavioral contract; partial handlers do not satisfy the gate.
- CI and release documentation must show per-platform evidence and any limitations.
- Platform-specific choices may differ internally but must preserve the public contract and explicitly reject unsupported options.

## Alternatives Considered

- Ship a smaller mobile-first matrix and defer desktop targets. Rejected for v1 based on the stated project scope.
- Keep all targets registered and describe implementations as best-effort. Rejected because it creates a false availability expectation.
