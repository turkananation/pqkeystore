# Integration Guide

`pqkeystore` is intended to be a custody component. The integrations below describe package boundaries; they do not imply tested end-to-end interoperability.

## `pqcrypto` / `pqforge`

* **Role**: These provide the actual cryptographic algorithms (post-quantum and classical).
* **Integration**: `pqkeystore` does not implement post-quantum mathematics. `PqForgeKeystoreCrypto` adapts pqforge 0.4.13 `wrapKeyWithPassphrase` and maps `PqWrappedKey` into PQKS. Buffer ownership for that path is recorded in [`PROVIDER_LIFECYCLE.md`](PROVIDER_LIFECYCLE.md). Dependency internals have not had an independent security review.

### Format Boundary

`PqWrappedKey` is pqforge's password-wrapped exported-key value. `PqEnvelope` / `.pqf` is a one-shot recipient-oriented content envelope, and `PqStreamingEnvelope` / `.pqfs` is a framed streaming content envelope. `pqkeystore` persists its own PQKS record and currently maps fields from `PqWrappedKey`; it does not store `.pqf` or `.pqfs` files. These names and formats are not interchangeable. See [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md).

## `pqthreshold`

* **Role**: Manages distributed key generation and threshold signature ceremonies.
* **Integration**: `pqthreshold` owns ceremonies and share mathematics. `putShare` / `useShare` check structural metadata and move one share. They do not import `pqthreshold`, and no end-to-end signing or DKG test exists. Treat them as custody helpers only. See [ADR-0005](adr/0005-threshold-share-boundary.md).

## `zeroize`

* **Role**: Provides secret-buffer utilities used by the facade.
* **Integration**: `use` copies the unwrap result into `SecretBytes` (`fromUint8List` copies; it does not take ownership), wipes that source with `secureZero`, and wipes the callback copy in `finally`. The adapter wipes the two plaintext copies it allocates during wrap. The passphrase `String` and pqforge-internal temporaries are not wiped. See [`PROVIDER_LIFECYCLE.md`](PROVIDER_LIFECYCLE.md). This is not a guarantee against runtime copies, memory dumps, or callback retention.

## `swissarmyknife`

* **Role**: A declared package dependency.
* **Integration**: The current public facade returns local `KsResult<T>`/`KsSuccess<T>`/`KsFailure<T>` types. It does not currently expose `swissarmyknife` `Result`; dependency use or removal should be resolved separately.

## `pqdga` / `pqtransport`

* **Role**: Downstream ecosystem packages that may consume key material.
* **Integration**: A downstream caller uses the public `PqKeystore(backend:, crypto:)` constructor and `use` as the access path. The caller must not retain or copy callback data unnecessarily; complete memory erasure is not guaranteed.

## Readiness

No end-to-end integration with these ecosystem packages is established by the current package tests. Track provider semantics, threshold interoperability, and the secret lifecycle in [`TRACKER.md`](TRACKER.md) and [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md).
