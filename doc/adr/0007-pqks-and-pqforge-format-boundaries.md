# ADR-0007: PQKS And pqforge Format Boundaries

- Status: Proposed
- Date: 2026-10-05

## Context

The project uses several similarly named formats with different jobs:

- PQKS is `pqkeystore`'s versioned backend record (`PQKS` magic) containing key metadata and crypto-wrapper fields.
- `pqforge`'s `PqWrappedKey` is a passphrase-wrapped exported-key value containing KDF/AEAD identifiers, salt, nonce, ciphertext, and key identity. Its JSON representation is not a PQKS record.
- `pqforge`'s `PqEnvelope` is a recipient-oriented one-shot content-encryption envelope. Its binary frame is length-prefixed and carries `PQF1` as a field; `.pqf` is a file suffix convention, not the frame's raw leading magic bytes.
- `pqforge`'s `PqStreamingEnvelope` is a distinct `PQFS` frame container for large/streamed content, with a signed/authenticated header and independently authenticated sequenced frames. `.pqfs` is its file suffix convention.

The resolved `pqforge` dependency is 0.4.6. `PqForgeKeystoreCrypto` calls `wrapKeyWithPassphrase`, then maps fields from `PqWrappedKey` into a custom `SealedRecord`; it does not produce or consume `.pqf`/`.pqfs` envelopes and does not currently store `PqWrappedKey.toJson()` verbatim.

## Decision

Keep these concepts distinct in API, storage, and documentation:

| Format | Owner | Purpose | Protection/keying model | Used by pqkeystore today |
| --- | --- | --- | --- | --- |
| PQKS | pqkeystore | Durable keystore record with metadata and versioned wrapper fields | Depends on the selected `PqKeystoreCrypto`; current adapter uses pqforge passphrase wrapping | Yes, as the backend record |
| `PqWrappedKey` | pqforge | Wrap one exported key for storage/custody | Password KDF plus AEAD; identity is authenticated | Yes, through a field mapping, not verbatim JSON |
| `PqEnvelope` / `.pqf` | pqforge | One-shot recipient-oriented content encryption | KEM-derived data-encryption key, AEAD payload, optional metadata/signature features | No |
| `PqStreamingEnvelope` / `.pqfs` | pqforge | Bounded-memory streaming content encryption | KEM-derived data-encryption key and per-frame AEAD; optional signed header | No |

PQKS is not a synonym for either pqforge content envelope. File suffixes must not drive record parsing; codecs identify formats from their own magic/version framing. V1 makes no `.pqf` or `.pqfs` import/export compatibility promise.

Before further wire-format code, decide and document the exact PQKS-to-provider mapping: which `PqWrappedKey` fields are copied into PQKS, how the provider wrapper version is represented, how metadata AAD is bound, and how old PQKS records migrate. Do not silently claim that the current field mapping is byte-for-byte `PqWrappedKey` serialization.

## Consequences

- Add format-selection tests proving PQKS, PQF1, and PQFS inputs are not confused or parsed by the wrong codec.
- Pin adapter compatibility tests against the resolved pqforge API/version and round-trip metadata, KDF, nonce, and ciphertext exactly.
- Keep content-envelope use cases and recipient-key workflows out of the keystore backend contract unless a separately reviewed import/export feature is specified.
- Explain in API and architecture docs that pqkeystore stores custody records; it is not the application file-encryption API.

## Alternatives Considered

- Store `.pqf` as the key record. Rejected as the default because it is a recipient-oriented content envelope, not the current passphrase-wrap model or PQKS metadata/lifecycle contract.
- Store `.pqfs` for ordinary key records. Rejected because its streaming framing solves large-content transport/storage and adds unrelated framing/signature semantics.
- Treat the `PqWrappedKey` JSON object as interchangeable with PQKS. Rejected because PQKS adds metadata, record identity, and its own wire version.

## Open Questions

- Should the PQKS v1 crypto section embed the public `PqWrappedKey` representation or keep a documented field mapping?
- Which provider fields are mandatory, and how are unknown future provider fields handled?
- What migration path is required if pqforge changes `PqWrappedKey` serialization or KDF defaults?
- Are import/export adapters for `.pqf` or `.pqfs` in scope at all? If yes, what trust and key-selection policy applies?
