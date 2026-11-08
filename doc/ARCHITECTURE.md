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
    MethodChannel -.-> Android[Android: AndroidKeyStore + files]
    MethodChannel -.-> iOS[iOS/macOS: data protection keychain]
    MethodChannel -.-> Windows[Windows: DPAPI files]
    MethodChannel -.-> Linux[Linux: Secret Service]
```

## Core Components

### 1. Application Layer

The application interacts exclusively with the `PqKeystore` facade. It provides raw key material and passphrases during setup, and receives temporary access to plaintext keys via the `use()` callback. Plaintext keys are never stored long-term in the app state.

### 2. PqKeystore Facade

This is the orchestrator. `put` asks `PqKeystoreCrypto` to wrap plaintext and then asks `PqKeystoreBackend` to store a `SealedRecord`. `use` retrieves the record, checks its identity and canonical AAD, unwraps, and passes plaintext to the callback. `SecretBytes.fromUint8List` copies, so the facade wipes the unwrap buffer immediately after the copy and wipes the callback copy in a `finally`. The public named constructor is `PqKeystore(backend:, crypto:)`.

### 3. PqKeystoreCrypto (Wrap/Unwrap)

Responsible for wrapping and unwrapping key material. `PqForgeKeystoreCrypto` calls pqforge 0.4.13 `wrapKeyWithPassphrase` and maps `PqWrappedKey` fields into `SealedRecord`; it does not serialize a `.pqf` or `.pqfs` content envelope. `SealedRecord` encodes wrapper parameters and ciphertext in PQKS framing. Parsing alone does not authenticate a record. Before unwrap, `use` rejects a record whose id or canonical AAD does not match the stored metadata.

### 4. PqKeystoreBackend (Storage)

Handles the persistence of the sealed PQKS blobs.

* **Memory**: Transient, used for testing or highly sensitive session keys.
* **File**: Stores blobs on disk, useful for desktop or pure-Dart environments.
* **Platform**: Delegates to a Flutter method channel implementing [contract v1](PLATFORM_CONTRACT.md). Native code stores one opaque PQKS blob per ID; Dart filters lists by decoding records. Per-platform design: [ADR-0009](adr/0009-native-backend-designs.md). On-device evidence status: [`PLATFORM.md`](PLATFORM.md).

## Defense in Depth

The intended architecture is layered, but the following are design goals, not verified current guarantees:

1. **Inner wrapping**: `PqForgeKeystoreCrypto` is the only crypto implementation in `lib/`. v1 unwraps with `PassphraseUnlock` only.
2. **Backend storage**: The backend stores encoded records. The channel contract is implemented on all five targets; which of those have a passing contract suite is [`PLATFORM.md`](PLATFORM.md), not this diagram. The file backend has no index. Someone who can replace a record file can replace its AAD with it, so the facade's AAD check is a consistency check, not an authenticity claim.

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
* `putShare` / `useShare` store and return one share. Structural metadata is checked (`1 <= t <= n`, 1-based index, non-empty scheme and ceremony ids). Share math and reconstruction are not implemented. See [ADR-0005](adr/0005-threshold-share-boundary.md).
