# Architecture

The `pqkeystore` package separates facade policy, crypto wrapping, and backend storage. The Dart structure exists, but native parity and security guarantees are incomplete; see [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md).

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
    MethodChannel -.-> Android[Android partial]
    MethodChannel -.-> iOS[iOS/macOS partial]
    MethodChannel -.-> Windows[Windows stub]
    MethodChannel -.-> Linux[Linux stub]
```

## Core Components

### 1. Application Layer

The application interacts exclusively with the `PqKeystore` facade. It provides raw key material and passphrases during setup, and receives temporary access to plaintext keys via the `use()` callback. Plaintext keys are never stored long-term in the app state.

### 2. PqKeystore Facade

This is the orchestrator. `put` asks `PqKeystoreCrypto` to wrap plaintext and then asks `PqKeystoreBackend` to store a `SealedRecord`. `use` retrieves and unwraps the record, calls the supplied body, clears the callback copy in a `finally` block, and disposes the `SecretBytes` wrapper. The resolved `SecretBytes.fromUint8List` copies its input, so the original unwrap buffer remains caller-owned and is not currently cleared by the facade. The public named constructor is verified by the passing facade tests.

### 3. PqKeystoreCrypto (Wrap/Unwrap)

Responsible for wrapping and unwrapping key material. `PqForgeKeystoreCrypto` calls pqforge 0.4.6 `wrapKeyWithPassphrase` and maps `PqWrappedKey` fields into `SealedRecord`; it does not serialize a `.pqf` or `.pqfs` content envelope. `SealedRecord` encodes wrapper parameters and ciphertext in PQKS framing. Parsing alone does not authenticate a record, and retrieval currently lacks a metadata-to-AAD consistency check.

### 4. PqKeystoreBackend (Storage)

Handles the persistence of the sealed PQKS blobs.

* **Memory**: Transient, used for testing or highly sensitive session keys.
* **File**: Stores blobs on disk, useful for desktop or pure-Dart environments.
* **Platform**: Delegates to a Flutter method channel. Android and Apple handlers are partial and contract-incompatible; Linux and Windows are stubs.

## Defense in Depth

The intended architecture is layered, but the following are design goals, not verified current guarantees:

1. **Inner wrapping**: A crypto provider is responsible for cryptographic protection. `StubKeystoreCrypto` is insecure. Authentication mode behavior depends on the adapter and is not uniform for every public unlock type.
2. **Backend storage**: The backend stores encoded records. The native method channel is incomplete across targets. The file backend's unkeyed index checksum is not adversarial authentication.

Do not infer hardware-backed protection, biometric enforcement, confidentiality under every configured mode, or cross-platform availability from this architecture diagram.

## Storage Format Boundaries

| Name | Owner and responsibility | Used here |
| --- | --- | --- |
| PQKS | `pqkeystore` record framing and metadata for a stored key | Yes; persisted by backends |
| `PqWrappedKey` | pqforge passphrase-based wrapping of one exported key | Yes; its fields are mapped into PQKS |
| `PqEnvelope` / `.pqf` | pqforge one-shot, KEM-recipient content encryption | No |
| `PqStreamingEnvelope` / `.pqfs` | pqforge authenticated streaming content encryption | No |

The formats differ in framing, purpose, and keying model. A filename suffix is not a decoder selector. The exact versioned mapping between the pqforge wrapper and PQKS, plus migration behavior, remains a design decision in [ADR-0007](adr/0007-pqks-and-pqforge-format-boundaries.md). Metadata is currently stored in cleartext; its privacy policy and key lifecycle are open in [ADR-0008](adr/0008-metadata-identity-and-key-lifecycle.md).

## Threshold Operations

For threshold cryptography, `pqkeystore` is intended to manage individual *shares*, not perform threshold mathematics.

* One share is stored per device.
* The ceremony is expected to be managed externally by `pqthreshold`; end-to-end integration is not established.
* `putShare` checks share kind and threshold metadata presence only. Full key reconstruction is not implemented by these helpers. See [ADR-0005](adr/0005-threshold-share-boundary.md).
