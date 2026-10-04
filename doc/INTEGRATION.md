# Integration Guide

`pqkeystore` is a foundational component. This document describes how it interacts with the rest of the Yardenah architecture.

### `pqcrypto` / `pqforge`

* **Role**: These provide the actual cryptographic algorithms (post-quantum and classical).
* **Integration**: `pqkeystore` does NOT implement math. It relies on `pqforge` to provide the implementation for `PqKeystoreCrypto`. When `put` is called, `pqforge` routines are used to derive keys from passphrases, encrypt the payload, and generate the PQKS blob.

### `pqthreshold`

* **Role**: Manages distributed key generation and threshold signature ceremonies.
* **Integration**: A single device rarely holds a complete, reconstructed key. Instead, `pqthreshold` generates a *share*. This share is passed to `PqKeystore.putShare`. During a signing event, `pqthreshold` calls `PqKeystore.useShare` to temporarily load the share, perform a partial signature, and immediately discard the share.

### `zeroize`

* **Role**: Ensures sensitive data is overwritten in memory, mitigating cold-boot and memory scraping attacks.
* **Integration**: `pqkeystore` uses `zeroize` aggressively. Plaintext arguments passed to `put` and the decrypted buffers provided to the `use` callback MUST be passed through `zeroize` immediately after their required lifespan ends.

### `swissarmyknife`

* **Role**: Utility library.
* **Integration**: `pqkeystore` utilizes the `Result` monad from `swissarmyknife` for functional error handling, replacing try/catch blocks and returning explicit success/failure types.

### `pqdga` / `pqtransport`

* **Role**: Networking and domain generation layers.
* **Integration**: These packages require keys to operate (e.g., TLS certificates, seed values). They depend on `pqkeystore` to load these keys securely via the `use` callback, establish the connection or state, and then allow the key to be cleared from memory.
