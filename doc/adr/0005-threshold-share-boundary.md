# ADR-0005: Threshold Share Custody Boundary

- Status: Accepted
- Date: 2026-10-04
- Accepted: 2026-11-08 (TRK-008). Ceremony interoperability stays a non-goal.

## Context

The facade exposes `putShare` and `useShare`. Custody of one share is this package's job. Share mathematics, distributed key generation, and combining shares are not.

## Decision

`pqkeystore` stores and returns individual shares. It does not validate share bytes, run a ceremony, or reconstruct a full key. Those belong to `pqthreshold`.

Structural invariants, enforced by `ThresholdMeta.validate` before a share is written and again before `useShare` unwraps one:

- `kind` is `KeyKind.thresholdShare`
- `schemeId` is non-empty
- `ceremonyId` is non-empty
- `t >= 1`, `n >= 1`, and `t <= n`
- `participantIndex` is in `1..n` (1-based, matching `pqthreshold.Share.index`)

`putShare` rejects anything else with `PolicyError` and does not call wrap. `put` applies the same rules when `kind` is `thresholdShare`, so the check cannot be bypassed. `useShare` refuses a record of any other kind — including a full key — with `PolicyError` and does not call unwrap. The callback receives that one share's plaintext. Cleanup matches `use`.

No public method takes more than one share. There is no reconstruction helper.

End-to-end `pqthreshold` interoperability is **not** claimed. A custody test is not a ceremony test.

## Consequences

- Metadata that passes `validate` is not evidence that the share is mathematically valid.
- Adding reconstruction requires a new ADR and a security review. It does not sneak in through `useShare`.

## Alternatives Considered

- Implement share math and ceremonies inside `pqkeystore`. Rejected: this package is custody, and project rules place the math in `pqthreshold`.
- Treat kind plus non-null metadata as sufficient. Rejected: `t`, `n`, the 1-based index, and the ids are checkable without doing math, and skipping them stores shares that `pqthreshold` would itself refuse.
- Claim ceremony support from the helpers. Rejected until an end-to-end test exists.
