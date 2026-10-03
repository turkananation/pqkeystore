# Claim Boundary

This document explicitly defines what security properties `pqkeystore` claims to provide and what it specifically does not claim. 

> **[!WARNING]**
> Always consult this document before assuming security properties. Any new security features must be added here as explicit claims.

## Current Claims

*   **PQKS Binary Format Integrity**: The keystore claims that data read back from the backend matches the format generated during storage. It validates magic bytes and version headers.
*   **Passphrase-Required Policy (v1)**: For keys wrapped with an `UnlockMethod.passphrase`, the keystore claims that the correct passphrase must be provided to the inner crypto layer to unwrap the data.
*   **Threshold Share Isolation**: The API claims to provide dedicated `putShare` and `useShare` endpoints to enforce a policy of storing shares rather than full keys, discouraging full in-memory reconstruction.
*   **AAD Binding**: If metadata is provided, the keystore claims that the metadata is cryptographically bound to the ciphertext (Authenticated Associated Data) during the wrap process, preventing tampering with the metadata without invalidating the key.

## Non-Claims (What we DO NOT guarantee)

*   **Cryptographic Strength**: `pqkeystore` DOES NOT claim that the underlying encryption is strong. The strength is entirely dependent on the injected `PqKeystoreCrypto` implementation.
*   **Platform Isolation**: We DO NOT claim protection against a compromised OS or root-level malware. If the OS is compromised, the outer storage layer is bypassed, leaving only the inner PQKS wrapper (which relies on the passphrase).
*   **Side-Channel Resistance**: The keystore layer DOES NOT claim resistance to timing, power, or memory-snooping side-channel attacks during the fraction of a second the key is in plaintext.
*   **Memory Safety in Callbacks**: We DO NOT claim that the user's `callback` in `use()` will not leak the key. The caller is responsible for not copying the buffer provided to the callback.

## Current State

> **[!CAUTION]**
> While `StubKeystoreCrypto` is active in the codebase, **WE CLAIM ZERO PRODUCTION SECURITY**. The stub does no encryption. All claims above are contingent on a proper `pqforge` implementation being injected.
