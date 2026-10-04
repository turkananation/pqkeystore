# ADR-0006: PQKS Record Invariants

- Status: Proposed
- Date: 2026-10-04

## Context

PQKS v1 records encode metadata and AAD, but the facade does not currently prove that AAD is the canonical encoding of the decoded metadata before unwrap. The decoder also accepts trailing bytes. Parser bounds and compatibility rules need to be explicit for an externally stored binary format.

## Decision

Define PQKS v1 as a strict, canonical record format: reject trailing bytes, malformed encodings, unsupported versions, and fields outside documented size limits. Before unwrap, recompute canonical AAD from the record metadata and require an exact match with the stored AAD. Bind the record's metadata ID to the requested backend ID. Decide and document size limits and forward-compatibility policy before implementation.

## Consequences

- Existing non-canonical blobs with trailing bytes will be rejected; migration implications must be considered before release.
- Tests must cover metadata tampering, ID mismatch, truncated and oversized fields, invalid encodings, trailing bytes, and valid round trips.
- Claim-boundary statements about metadata authentication remain conditional until these checks and tamper tests are complete.

## Alternatives Considered

- Rely only on the crypto provider to compare stored AAD with supplied stored AAD. Rejected because it does not establish a binding between AAD and decoded metadata.
- Permit trailing bytes for future extensions. Rejected for v1; extensions need an explicit versioned encoding rule.

## Open Questions

- What are the maximum encoded record and per-field sizes?
- Does the current canonical metadata encoder have a stable cross-version serialization contract?
- What migration or compatibility behavior is required for blobs already stored before strict decoding?
