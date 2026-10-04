# API Reference

This document outlines the core public APIs for `pqkeystore`.

## `PqKeystore`

The main facade class used by applications.

### Methods

* `Future<KsResult<void>> put({required String id, required List<int> keyMaterial, required String passphrase, KeyMetadata? metadata})`
    Stores a new key. The `keyMaterial` is immediately wrapped.
* `Future<KsResult<T>> use<T>({required String id, required String passphrase, required Future<T> Function(List<int> keyData) callback})`
    The preferred method for accessing a key. Unwraps the key, passes it to the `callback`, and guarantees the buffer is zeroized after the callback completes.
* `Future<KsResult<void>> delete({required String id})`
    Removes a key from the backend.
* `Future<KsResult<List<String>>> list()`
    Returns a list of all stored key IDs.
* `Future<KsResult<KeyMetadata?>> metadata({required String id})`
    Retrieves the public metadata for a key without unwrapping the secret material.
* `Future<KsResult<void>> putShare({required String id, required List<int> shareMaterial, ...})`
    Stores a threshold share.
* `Future<KsResult<T>> useShare<T>({required String id, required Future<T> Function(List<int> shareData) callback})`
    Utilizes a threshold share securely.

## Data Structures

### `UnlockMethod`

Defines how a key can be unlocked.

* `passphrase`: Requires a user-provided string.
* `biometric`: Relies on OS biometric prompts (future).
* `none`: Unprotected at the inner layer (relies entirely on OS).

### `KeyMetadata`

Public information associated with a key, stored in plaintext alongside the wrapped blob.

* `type`: e.g., 'symmetric', 'asymmetric', 'share'.
* `algorithm`: e.g., 'AES256', 'Kyber768'.
* `createdAt`: Timestamp.

### `SealedRecord`

The internal representation of data handed to the backend. Contains the `PQKS` blob and the plaintext `KeyMetadata`.

### `PQKS Format`

Post-Quantum Key Store binary format.

* `Magic bytes`: (e.g., `PQKS`)
* `Version`: format version integer.
* `Salt/Nonce`: Cryptographic parameters.
* `Ciphertext`: Wrapped key material.
* `MAC/Tag`: Integrity check.

### `KsResult<T>`

*Note: To be replaced by `swissarmyknife` `Result`.*
Represents either a success containing type `T` or a failure containing an error.

### Errors

Common error cases include:

* `NOT_FOUND`: Key ID does not exist.
* `AUTH_FAILED`: Incorrect passphrase or wrapping validation failed.
* `BACKEND_ERROR`: The storage backend failed (e.g., OS keychain error).
* `CORRUPTED`: The PQKS blob integrity check failed.
