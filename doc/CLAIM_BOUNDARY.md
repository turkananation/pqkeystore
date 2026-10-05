# Claim Boundary

This document explicitly defines what security properties `pqkeystore` claims to provide and what it specifically does not claim.

> **[!WARNING]**
> Always consult this document before assuming security properties. Any new security features must be added here as explicit claims.

## Implemented Behavior (Limited Claims)

* **PQKS framing**: The codec recognizes the `PQKS` magic and supported version and decodes the defined fields. This is format parsing, not a claim that a record or backend index is authenticated against an attacker. The current decoder accepts trailing bytes; see [`BUGS.md`](BUGS.md).
* **Passphrase input policy**: `PqKeystore.put` rejects `PlatformUnlock` for v1 and accepts passphrase-based unlock variants. This describes API policy only; cryptographic strength and exact provider semantics depend on the injected `PqKeystoreCrypto` implementation.
* **Share helper policy**: `putShare` requires `KeyKind.thresholdShare` and non-null threshold metadata, then delegates to generic storage. It does not establish that share parameters are valid or that a threshold ceremony has succeeded.
* **Callback cleanup attempt**: `use` clears the callback copy in a `finally` block and disposes the `SecretBytes` wrapper. The original unwrap buffer ownership and complete memory-erasure behavior have not been verified, so complete zeroization is not claimed.
* **Metadata confidentiality**: PQKS serializes `KeyMetadata` in cleartext. Do not place secrets or sensitive personal data in metadata unless the selected backend's confidentiality behavior has been explicitly reviewed.

## Planned Invariant, Not Yet Claimed

* **Metadata AAD binding**: `put` computes canonical metadata AAD and supplies it to the crypto adapter. On retrieval, the facade does not currently verify that the stored AAD equals canonical AAD recomputed from stored metadata. Therefore end-to-end metadata tamper detection is not currently claimed. See [`BUGS.md`](BUGS.md) and [ADR-0006](adr/0006-pqks-record-invariants.md).

## Non-Claims (What we DO NOT guarantee)

* **Cryptographic Strength**: `pqkeystore` DOES NOT claim that the underlying encryption is strong. The strength is entirely dependent on the injected `PqKeystoreCrypto` implementation.
* **Platform availability or isolation**: The package registers five platforms, but current native support is incomplete and contract-incompatible. No claim of operational OS isolation, hardware backing, biometric enforcement, or equivalent protection across platforms is made.
* **File index authenticity**: The current index checksum is unkeyed and is not adversarial tamper authentication.
* **Side-channel resistance**: No resistance to timing, power, or memory-snooping attacks is claimed.
* **Callback confinement**: The callback can copy or retain the plaintext it receives. The API cannot prevent caller leakage or copies outside the buffer it clears.
* **Complete memory erasure**: Dart/runtime copies, provider-owned buffers, and dependency disposal semantics are not fully verified; overwriting one callback buffer is not proof of complete erasure.
* **Threshold validity**: Metadata checks do not validate share mathematics or a DKG/signing ceremony.
* **Format interoperability**: PQKS is not the pqforge `.pqf` or `.pqfs` content-envelope format. No cross-format import/export compatibility is claimed.

## Current State

> **[!CAUTION]**
> `StubKeystoreCrypto` is insecure and provides no production security. A `PqForgeKeystoreCrypto` adapter exists, but its provider behavior and the complete package/platform system have not been independently validated. Do not infer production readiness from adapter presence. See [`TRACKER.md`](TRACKER.md) for release gates.
