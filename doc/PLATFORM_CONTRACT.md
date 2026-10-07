# Platform Channel Contract v1

Status: **Proposed** (ADR-0002). This is the normative specification that all five native implementations and the Dart client implement. The executable form is [`test/contract/reference_native_store.dart`](../test/contract/reference_native_store.dart) (reference native behavior) and [`test/contract/platform_contract_suite.dart`](../test/contract/platform_contract_suite.dart) (behavioral suite run against the reference in unit tests and against each real platform in [`example/integration_test/`](../example/integration_test/)). If prose and tests disagree, the tests win and this document is a bug.

## 1. Channel

| Property | Value |
| --- | --- |
| Name | `com.yardenah.pqkeystore/store` (frozen; identical on every platform) |
| Codec | Flutter `StandardMethodCodec` |
| Version | `1`, reported by `platformInfo.contractVersion` |

The Dart client calls `platformInfo` once before its first operation and refuses to operate (`CONTRACT_MISMATCH`) if the version or result shape differs. A failed handshake is not cached.

## 2. Methods

Native code stores exactly one opaque byte string per ID. It never parses PQKS and never stores metadata separately: list filtering is done in Dart by decoding each PQKS record. Every write is therefore a single native operation, and no ID prefix is reserved (`putJson`/`getJson` and the `__meta__` sidecar are removed).

| Method | Arguments | Success result | Notes |
| --- | --- | --- | --- |
| `platformInfo` | ignored | `{contractVersion: int, os: String, backend: String, supportedOptions: List<String>}` | `os` ∈ `android, ios, macos, windows, linux`. `backend` is diagnostic only. `supportedOptions` ⊆ §5 capability names, and is evaluated *now* (it may change, e.g. when a lock screen is removed). |
| `put` | `{id: String, data: Uint8List, options: Map}` | `null` | Upsert. Atomic per ID: after any failure the previous value (or absence) is intact. |
| `get` | `{id: String}` | `Uint8List` or `null` | `null` ⇔ not found. Never `NOT_FOUND` errors. |
| `delete` | `{id: String}` | `bool` | `true` iff a valid entry existed and was removed; `false` if absent. |
| `contains` | `{id: String}` | `bool` | Must not trigger authentication prompts. |
| `listIds` | none (`null`) | `List<String>` | Unordered; the client sorts. Contains exactly the IDs for which `contains` is `true`. Must not prompt for per-item authentication (Linux may prompt to unlock a locked collection). |

Unknown methods → `notImplemented` (`MissingPluginException` in Dart).

Argument maps are **closed**: any key not listed above → `INVALID_ARGS`. A non-map (or `null`) argument for `put/get/delete/contains`, or any non-null argument for `listIds` → `INVALID_ARGS`.

## 3. IDs

- Non-empty, at most **256 bytes** UTF-8, no U+0000, well-formed Unicode.
- Compared exactly: no normalization, no case folding (`Key`, `key`, NFC `café` and NFD `café` are four distinct IDs).
- Opaque: never interpreted as a path, filename, or attribute syntax. Backends map IDs injectively (see ADR-0009).
- Validated by the Dart client before sending (it alone can detect unpaired surrogates, which the codec would otherwise replace with U+FFFD) and re-validated natively.

**Known limitation L1:** the Linux embedder's codec truncates strings at U+0000 before the plugin sees them, so Linux cannot detect an embedded NUL; the Dart client is the enforcement point there. The suite skips that single case on Linux.

## 4. Data

`data` is 1 to **1,048,576** bytes (`Uint8List`). Empty or larger data → `INVALID_ARGS`. Records returned by `get` are guaranteed to be within the same bounds; anything else stored is `CORRUPT`.

## 5. Options

`options` must contain exactly these four keys:

| Key | Type | Values |
| --- | --- | --- |
| `requireUserPresence` | bool | |
| `requireBiometric` | bool | |
| `accessibility` | String | `platformDefault`, `whenUnlocked`, `afterFirstUnlock` |
| `synchronizable` | bool | |

Missing/extra keys, wrong types (including integers posing as booleans), or unknown `accessibility` values → `INVALID_ARGS`.

Each non-default value requests a capability:

| Capability name | Requested by |
| --- | --- |
| `requireUserPresence` | `requireUserPresence: true` |
| `requireBiometric` | `requireBiometric: true` |
| `accessibility.whenUnlocked` | `accessibility: whenUnlocked` |
| `accessibility.afterFirstUnlock` | `accessibility: afterFirstUnlock` |
| `synchronizable` | `synchronizable: true` |

Evaluation order is normative:

1. Shape validation (`INVALID_ARGS`).
2. Every requested capability must be in the current `supportedOptions`; otherwise `UNSUPPORTED_OPTION`. **Nothing is silently ignored or downgraded.**
3. Platform-independent combination rule: `synchronizable` with `requireUserPresence` or `requireBiometric` → `UNSUPPORTED_OPTION`.

The Dart client applies steps 2–3 before calling `put`; natives apply all three regardless.

Options apply to writes only. Reads of an access-controlled entry may show an OS authentication prompt.

## 6. Errors

`PlatformException.code` is one of:

| Code | Meaning | Dart mapping |
| --- | --- | --- |
| `INVALID_ARGS` | Contract violation in arguments | `PlatformError` |
| `UNSUPPORTED_OPTION` | Option/combination not enforceable here | `PlatformError` |
| `UNAVAILABLE` | OS storage facility absent (no Secret Service, missing keychain entitlement, keystore unavailable) | `PlatformError` |
| `LOCKED` | Present but locked (device locked, collection locked, before first unlock) | `PlatformError` |
| `USER_CANCELLED` | User dismissed a prompt | `Cancelled` |
| `AUTH_FAILED` | User failed authentication | `PlatformError` |
| `KEY_INVALIDATED` | Protecting OS key permanently gone; entry unrecoverable | `PlatformError` |
| `CORRUPT` | Entry exists but fails decoding/authentication | `PlatformError` |
| `STORAGE_ERROR` | Any other OS/I/O failure | `PlatformError` |

Dart-only: `CONTRACT_MISMATCH` (handshake or result-shape violation). Unknown native codes are mapped to `STORAGE_ERROR`.

Messages are diagnostic, contain **no record data**, and never carry stack traces; `details` is unused.

## 7. Consistency and concurrency

- Each implementation executes calls in arrival order on a single serial executor (Android: dedicated thread; Apple: serial dispatch queue; Linux: exclusive worker thread; Windows: platform thread).
- `put` is atomic per ID. Concurrent `put`s to one ID leave exactly one complete value.
- Cross-process access from multiple instances of the same app is not coordinated beyond OS atomic-replace guarantees (ADR-0009).

## 8. Client-side guarantees (Dart)

- `getSealed` rejects records whose decoded metadata ID differs from the requested ID (`FormatError`), and undecodable bytes (`FormatError`).
- `putSealed` rejects a record whose metadata ID differs from the storage ID.
- `list` propagates corrupt entries instead of hiding them; `listIds()` + `delete()` allow recovery.

## 9. Changing the contract

Any change to names, types, bounds, codes, or semantics requires a version bump, updates to all five natives, the reference store, and the suite in the same change.
