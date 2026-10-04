# ADR-0005: Threshold Share Custody Boundary

- Status: Proposed
- Date: 2026-10-04

## Context

The facade exposes `putShare` and `useShare`. The current `putShare` checks the key kind and presence of threshold metadata, then delegates to generic `put`; `useShare` delegates to generic `use`. The repository does not currently demonstrate parameter validation or an end-to-end `pqthreshold` ceremony.

## Decision

Keep `pqkeystore` responsible for custody and lifecycle of an individual share. Specify which metadata invariants it validates and which cryptographic/ceremony validation remains the responsibility of `pqthreshold`. Full-key reconstruction must never occur implicitly in this package; any future reconstruction flow requires a separate explicit design and security review.

## Consequences

- API documentation must distinguish storage helpers from threshold cryptographic validation.
- Add tests for accepted/rejected threshold metadata and integration tests before claiming ecosystem interoperability.
- Do not claim a share is valid merely because it has `KeyKind.thresholdShare` and non-null threshold metadata.

## Alternatives Considered

- Implement share math and ceremonies inside `pqkeystore`. Rejected because the package is a custody layer and project rules place math in crypto/threshold packages.
- Claim complete threshold support from the current helper methods. Rejected because validation and ceremony integration are not established.
