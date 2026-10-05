# ADR-0008: Metadata, Identity, And Key Lifecycle

- Status: Proposed
- Date: 2026-10-05

## Context

`KeyMetadata` is serialized in plaintext in each PQKS record. It includes a caller-selected ID, key kind, algorithm, creation time, purpose, version, rotation lineage, threshold metadata, and tags. The API currently has no rotation, passphrase-change, backup/restore, migration, or secure-delete operation; repeated `put` replaces an existing ID in storage. `KeyId` has no explicit character, length, normalization, or reserved-name policy. The platform backend reserves the `__meta__` prefix internally, while the file backend sanitizes IDs for filenames.

## Decision

Before freezing the public API, specify:

- ID character set, length, normalization, case sensitivity, uniqueness scope, and reserved namespaces.
- Which metadata fields may be persisted in cleartext, which fields are authenticated, and whether any metadata is forbidden from containing secrets or personal data.
- Whether `put` is create-only or replace/upsert; how `version` and `rotatedFrom` relate to that operation; and how concurrent updates are resolved.
- V1 semantics for passphrase change/re-wrap, rotation, deletion, backup/restore, cross-device migration, and format upgrades. Explicitly distinguish logical deletion from guaranteed physical erasure.
- Which behaviors are intentionally out of scope for v1 and therefore must not be implied by API names or docs.

Prefer a portable logical ID independent of any backend filename or native storage key. Do not use an undocumented prefix convention as an application-visible namespace.

## Consequences

- Add validation and compatibility tests for accepted IDs and metadata.
- Ensure each backend maps a logical ID injectively and cannot reinterpret it as a path or internal metadata key.
- Document metadata confidentiality, overwrite, delete, recovery, and migration semantics before release.
- Any new lifecycle API requires a separate migration/compatibility review; it must not reconstruct key material outside the preferred callback flow.

## Alternatives Considered

- Let each backend sanitize or normalize IDs independently. Rejected because IDs would alias differently across platforms.
- Treat every metadata field as harmless because it is not key bytes. Rejected because purpose, tags, algorithm, and threshold identity may be sensitive in deployments.
- Promise secure erase from filesystem or OS keychain deletion. Rejected without platform-specific evidence; logical deletion is not physical-media erasure.

## Open Questions

- Are IDs globally unique per app, per backend, or per tenant/namespace?
- Which metadata fields are sensitive and should be minimized, encrypted, or omitted?
- Is overwriting an existing ID allowed, and what should concurrent writes do?
- Does v1 require re-wrap/rotation and backup/restore, or are those explicit non-goals?
- What migration support is required for PQKS records when the format or provider adapter changes?
