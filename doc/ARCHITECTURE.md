# Architecture

The `pqkeystore` package is designed with a layered architecture to provide strong security guarantees, modularity, and cross-platform consistency.

## Layer Diagram

```mermaid
flowchart TD
    App[Application Code] --> PqKeystoreFacade[PqKeystore (Facade)]
    PqKeystoreFacade --> PqKeystoreCrypto[PqKeystoreCrypto (Wrap/Unwrap)]
    PqKeystoreFacade --> PqKeystoreBackend[PqKeystoreBackend (Storage)]
    
    PqKeystoreBackend --> Mem[MemoryKeystoreBackend]
    PqKeystoreBackend --> File[FileKeystoreBackend]
    PqKeystoreBackend --> Plat[PlatformBackend]
    
    Plat -.-> MethodChannel((MethodChannel))
    MethodChannel -.-> Android[Android Keystore]
    MethodChannel -.-> iOS[iOS/macOS Keychain]
    MethodChannel -.-> Windows[Windows DPAPI]
    MethodChannel -.-> Linux[Linux Secret Service]
```

## Core Components

### 1. Application Layer

The application interacts exclusively with the `PqKeystore` facade. It provides raw key material and passphrases during setup, and receives temporary access to plaintext keys via the `use()` callback. Plaintext keys are never stored long-term in the app state.

### 2. PqKeystore Facade

This is the orchestrator. When a key is added (`put`), it asks `PqKeystoreCrypto` to wrap the plaintext into a PQKS blob, and then asks `PqKeystoreBackend` to store that blob. When a key is requested (`use`), it retrieves the blob from the backend, unwraps it via crypto, executes the callback, and ensures the plaintext is zeroized.

### 3. PqKeystoreCrypto (Wrap/Unwrap)

Responsible for the cryptographic binding of the key material. It converts plaintext into the sealed `PQKS` (Post-Quantum Key Store) binary format. This involves encryption and integrity checks (MAC/AEAD), typically relying on the `pqforge` package.

### 4. PqKeystoreBackend (Storage)

Handles the persistence of the sealed PQKS blobs.

* **Memory**: Transient, used for testing or highly sensitive session keys.
* **File**: Stores blobs on disk, useful for desktop or pure-Dart environments.
* **Platform**: Delegates storage to the operating system's native secure enclave or keychain.

## Defense in Depth

The architecture relies on a "Defense in Depth" strategy:

1. **Inner Wrap (PQKS)**: The key material is encrypted and authenticated by `PqKeystoreCrypto` before it ever leaves the Dart environment. This binds the key to a passphrase or biometric challenge and provides format integrity.
2. **Outer Protection (OS)**: The resulting PQKS blob is then handed to the OS via the `PlatformBackend`. The OS applies its own layer of security (e.g., hardware-backed encryption, process isolation, DPAPI).

If the OS storage is compromised, the attacker only obtains the encrypted PQKS blob, which still requires the passphrase/challenge to unwrap.

## Threshold Operations

For threshold cryptography, `pqkeystore` manages individual *shares*, not the full key.

* One share is stored per device.
* The ceremony to utilize these shares is managed externally by `pqthreshold`.
* Full key reconstruction in a single memory space is considered an anti-pattern and defaults to OFF. Use `putShare` and `useShare` to manage partial keys.
