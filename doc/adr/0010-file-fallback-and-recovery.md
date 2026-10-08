# ADR-0010: File Fallback, Tombstones, And File-Store v1

- Status: Proposed
- Date: 2026-10-07
- Depends on: ADR-0001, ADR-0009, ADR-0002
- Supersedes parts of: ADR-0003 (index design is removed; see below)

## Context

Contract v1 made platform storage the preferred backend, but the OS facility can be absent or unusable (no Secret Service on headless Linux, missing keychain entitlement on an unsigned macOS build, no usable default collection). Refusing to write in those cases pushes applications toward insecure ad-hoc storage. The previous `FileKeystoreBackend` had its own problems: sanitized file names collided, a mutable unkeyed FNV index could be redirected to files outside the store directory, replacement deleted the old file before the new one was durable, and concurrent writes raced.

## Decision

1. **Opt-in fallback.** `FallbackKeystoreBackend(secure: PlatformKeystoreBackend(...), fallback: FileKeystoreBackend(...))` is the only fallback path. It triggers *only* on `PlatformError(code: UNAVAILABLE)` from the secure backend. `LOCKED`, `USER_CANCELLED`, `AUTH_FAILED`, `CORRUPT`, and option-rejection errors are surfaced, never converted into file writes. If `PlatformStoreOptions` request capabilities the file store cannot enforce, the write fails with `UNSUPPORTED_OPTION`.
2. **Dual-read, migrate-on-write.** Reads consult the fallback copy first (a fallback copy is never older than the secure copy), then the secure store. A successful secure write removes the fallback copy (or rewrites it identical if removal fails). `migrateToSecure()` moves every fallback record into secure storage as-is and deletes the fallback copy.
3. **Tombstones.** A `delete` that finds the secure store unavailable leaves a `.deleted` JSON marker naming the ID. `list()` and `migrateToSecure()` apply pending tombstones to the secure store as soon as it is reachable, so a deleted record cannot resurface.
4. **File store v1 replaces the old design.** One raw PQKS file per record, named `hex(SHA-256(UTF-8 ID)).pqks`, in a dedicated directory. **No index**: existence is derived from directory entries cross-checked against the embedded ID, which removes the outside-path redirection class entirely. Replacement is temp-file + rename; temp files older than 10 minutes are reclaimed. On first use of a legacy directory the backend adopts it: sanitized names are re-encoded, `.pqks-index.json` is deleted, and a `.pqkeystore-layout` marker is written. On POSIX desktops the directory is `0700`, files `0600`, verified after `chmod`.
5. **Protection of fallback data is the caller's responsibility.** A `.pqks` file is at rest exactly as protected as its inner `PqKeystoreCrypto` (e.g. `PqForgeKeystoreCrypto` passphrase wrapping). Metadata is cleartext. Use a dedicated directory.

## Consequences

- The old `.pqks-index.json` and FNV checksum disappear. Downgrade to a build without ADR-0010 ignores the marker and may misread the directory; do not downgrade.
- Contract tests now exercise the fallback indirectly through `FallbackKeystoreBackend` unit tests; platforms still pass the same suite via their secure backend.
- Security claims are scoped: fallback files are only as strong as the passphrase-derived wrapping inside the PQKS record.
- `StorageLocation`/`locate()` expose where a record lives without touching plaintext.

## Alternatives Considered

- **Automatic file fallback inside `PlatformKeystoreBackend`.** Rejected: it hides an unavailability signal the application should surface, and it makes the choice of "secure vs file" invisible to the caller.
- **Keep the sanitized-name + index design.** Rejected: names collide, and the index can be redirected to files outside the store. v1 keeps an adoption path so existing users keep their data.
- **Fall back on `LOCKED` or cancelled prompts.** Rejected: a locked device is a transient state, and silent downgrades would defeat user-presence protections.
- **Do not adopt legacy layouts.** Rejected: adoption is cheap, reversible, and keeps existing users working.

## Open Questions

- Should `FallbackKeystoreBackend` expose a `onLocationChanged` stream for UI indicators?
- Should tombstones carry a timestamp (and expire) to bound directory growth?
