# pqkeystore_example

A simple demonstration of how to use the `pqkeystore` package in a Flutter application.

## Overview

This example app demonstrates the core lifecycle of a key using the `pqkeystore` API:

1. **Put**: Storing a secret with a passphrase.
2. **List**: Viewing available keys in the store.
3. **Use**: Retrieving and utilizing the key securely via a callback.
4. **Delete**: Removing the key from storage.

## Warning

> **[!CAUTION]**
> The demo key material is freshly generated random bytes for demonstration
> purposes, and only the *length* of the unwrapped plaintext is displayed. The
> storage backend is the real platform backend (AndroidKeyStore, the Apple
> keychain, DPAPI, or the Secret Service) and the wrapping adapter is
> `PqForgeKeystoreCrypto`; `StubKeystoreCrypto` is **NOT SECURE** and is never
> used on this path. Do not treat this example as a complete application
> key-generation and passphrase policy.
