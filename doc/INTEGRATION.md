# Integration Guide

`pqkeystore` is intended to be a custody component. The integrations below describe package boundaries; they do not imply tested end-to-end interoperability.

## `pqcrypto` / `pqforge`

* **Role**: These provide the actual cryptographic algorithms (post-quantum and classical).
* **Integration**: `pqkeystore` does not implement post-quantum mathematics. `PqForgeKeystoreCrypto` adapts the `pqforge` wrapping API. The adapter exists, but dependency internals and security properties have not been independently audited in this project review.

## `pqthreshold`

* **Role**: Manages distributed key generation and threshold signature ceremonies.
* **Integration**: `pqthreshold` is the expected owner of threshold ceremonies and share mathematics. The current `putShare` checks the metadata kind and that threshold metadata exists; `useShare` delegates to `use`. An end-to-end signing or DKG integration has not been demonstrated, so the methods should be treated as custody helpers only.

## `zeroize`

* **Role**: Provides secret-buffer utilities used by the facade.
* **Integration**: `use` copies the unwrap result into `SecretBytes`, passes a separate callback copy, clears that callback buffer in `finally`, and disposes the wrapper. Ownership and disposal semantics for the original unwrap buffer have not been verified. This is not a guarantee against runtime copies, memory dumps, or callback retention.

## `swissarmyknife`

* **Role**: A declared package dependency.
* **Integration**: The current public facade returns local `KsResult<T>`/`KsSuccess<T>`/`KsFailure<T>` types. It does not currently expose `swissarmyknife` `Result`; dependency use or removal should be resolved separately.

## `pqdga` / `pqtransport`

* **Role**: Downstream ecosystem packages that may consume key material.
* **Integration**: A downstream caller can use `use` as the preferred access path once the public constructor/API blocker is fixed. The caller must not retain or copy callback data unnecessarily; complete memory erasure is not guaranteed.

## Readiness

No end-to-end integration with these ecosystem packages is established by the current package tests. Track provider semantics, threshold interoperability, and the secret lifecycle in [`TRACKER.md`](TRACKER.md) and [ADR-0004](adr/0004-unlock-and-secret-lifecycle.md).
