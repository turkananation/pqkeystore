# pqkeystore_example

A simple demonstration of how to use the `pqkeystore` package in a Flutter application.

## Overview

This example app demonstrates the core lifecycle of a key using the `pqkeystore` API:

1. **Put**: Storing a simulated secret with a passphrase.
2. **List**: Viewing available keys in the store.
3. **Use**: Retrieving and utilizing the key securely via a callback.
4. **Delete**: Removing the key from storage.

## Warning

> **[!CAUTION]**
> This example is configured to use `MemoryKeystoreBackend` and `StubKeystoreCrypto` for demonstration purposes. **It provides NO SECURITY**. Do not use this configuration or code verbatim in a production application handling real secrets.
