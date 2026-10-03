# pqkeystore

**Post-quantum key management layer for Dart/Flutter.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0--dev.1-orange.svg)](https://github.com/turkananation/pqkeystore/releases)

`pqkeystore` provides best-in-class custody for ML-KEM, ML-DSA, SLH-DSA,
classical, hybrid, and **threshold** secret key material — with first-class
support for Android, iOS, macOS, Windows, and Linux.

> [!CAUTION]
> **v0.1.0-dev.1** ships with `StubKeystoreCrypto` which is **NOT SECURE**.
> It exists solely for structural testing. Production wrap/unwrap requires
> wiring [`pqforge`](https://github.com/turkananation/pqforge).

---

## Architecture

```text
┌──────────────────────────────────────────────┐
│                  Application                 │
├──────────────────────────────────────────────┤
│               PqKeystore façade              │
│           put · use · delete · list          │
│         putShare · useShare · metadata       │
├─────────────────────┬────────────────────────┤
│  PqKeystoreCrypto   │   PqKeystoreBackend    │
│   wrap / unwrap     │  Memory│File│Platform  │
├─────────────────────┘────────────────────────┤
│              OS secure storage               │
│  Android Keystore · iOS/macOS Keychain       │
│  Windows DPAPI · Linux libsecret / file      │
└──────────────────────────────────────────────┘
```

**Plaintext only exists inside `PqKeystore.use(callback)`**. The OS stores
already-sealed PQKS blobs — defense in depth.

## Key Design Principles

- **Custody only** — no lattice math, no PQC primitives. That's
  [`pqcrypto`](https://github.com/turkananation/pqcrypto).
- **`use(callback)` API** — plaintext must not escape; buffers are zeroed after
  the callback returns.
- **Threshold-first** — store and use individual shares; full reconstruction is
  high-friction, explicit, and default **off**.
- **Evidence-oriented claims** — see [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md).

## Quick Start

```dart
import 'package:pqkeystore/pqkeystore.dart';

// ⚠️ StubKeystoreCrypto is NOT SECURE — structure tests only.
final crypto = StubKeystoreCrypto();
final backend = MemoryKeystoreBackend();
final keystore = PqKeystore(backend: backend, crypto: crypto);

final metadata = KeyMetadata(
  id: KeyId('my-ml-kem-key'),
  kind: KeyKind.mlKemSecret,
  algorithm: 'ML-KEM-768',
  createdAt: DateTime.now(),
);

// Store
final passphrase = Uint8List.fromList(utf8.encode('hunter2'));
await keystore.put(
  metadata,
  secretKeyBytes,
  PassphraseUnlock(passphrase),
);

// Use — plaintext zeroed automatically after callback
final result = await keystore.use(
  KeyId('my-ml-kem-key'),
  PassphraseUnlock(passphrase),
  (plaintext) async {
    // Use the key material here
    return doSomething(plaintext);
  },
);
```

## Yardenah Post-Quantum Stack

| Package | Role |
| --------- | ------ |
| **pqcrypto** | ML-KEM / ML-DSA / SLH-DSA primitives |
| **pqforge** | Application crypto, hybrids, envelopes, wrap/unwrap |
| **pqkeystore** | Key custody & management (this package) |
| **pqthreshold** | VSS, DKG, FROST / threshold shares |
| **pqdga** | Deterministic namespace / rendezvous material |
| **pqtransport** | Transport-layer key management |
| **zeroize** | Secret lifecycle, multi-pass zeroing, SecretBytes |
| **swissarmyknife** | Result, StateMachine, validation |

## Platform Support

| Platform | Backend | Mechanism |
| ---------- | --------- | ----------- |
| Android | `android-keystore` | AES-GCM in Android Keystore; blobs in SharedPreferences |
| iOS | `keychain` | Generic password, `ThisDeviceOnly` |
| macOS | `keychain` | Same as iOS |
| Windows | `dpapi` | `CryptProtectData` `UI_FORBIDDEN` |
| Linux | `libsecret` / file | Secret Service or XDG `0600` fallback |

## PQKS Binary Format

All sealed records use the PQKS wire format:

| Field | Encoding |
| ------- | ---------- |
| Magic | `0x50 0x51 0x4B 0x53` ("PQKS") |
| Version | uint32 BE |
| wrapAlg | length-prefixed UTF-8 |
| metadata | length-prefixed JSON UTF-8 |
| aad | length-prefixed bytes |
| nonce | length-prefixed bytes |
| kdfParams | length-prefixed JSON UTF-8 |
| ciphertext | length-prefixed bytes |

## Documentation

- [`doc/INDEX.md`](doc/INDEX.md) — Documentation index
- [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) — System architecture
- [`doc/API.md`](doc/API.md) — API reference
- [`doc/PLATFORM.md`](doc/PLATFORM.md) — Platform support details
- [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) — Security claims & boundaries
- [`AGENTS.md`](AGENTS.md) — Agent rules & conventions
- [`CONTINUE.md`](CONTINUE.md) — Next steps & continuation tasks
- [`SECURITY.md`](SECURITY.md) — Security policy

## License

MIT — Copyright 2024–2026 Yardenah PQ / Turkana Nation.
