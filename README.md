# pqkeystore

**Key custody and lifecycle primitives for Dart/Flutter.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0--dev.1-orange.svg)](https://github.com/turkananation/pqkeystore/releases)

`pqkeystore` provides a facade for wrapping, storing, and temporarily using key
material. It does not implement post-quantum mathematics. Although the package
registers Android, iOS, macOS, Windows, and Linux, native implementations are
incomplete; all five remain v1 production gates. See the
[platform status](doc/PLATFORM.md) and [production tracker](doc/TRACKER.md).

> [!CAUTION]
> **This package is not production-ready.** `StubKeystoreCrypto` is **NOT
> SECURE** and exists for structural testing only. A `PqForgeKeystoreCrypto`
> adapter is present, but crypto-provider behavior, secret-buffer lifecycle,
> and native storage have not completed production verification. Do not use the
> stub for real key material.

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
│             Native storage (incomplete)       │
│  Android · iOS · macOS · Windows · Linux (v1) │
└──────────────────────────────────────────────┘
```

`put` accepts plaintext input for wrapping; `use(callback)` is the preferred
retrieval path. The facade clears its callback buffer in a `finally` block, but
cannot prevent copies or guarantee complete process-memory erasure. Backend
protection varies and is not yet production-verified.

## Key Design Principles

- **Custody only** — no lattice math, no PQC primitives. That's
  [`pqcrypto`](https://github.com/turkananation/pqcrypto).
- **`use(callback)` API** — preferred access path. The facade clears a callback
  buffer in `finally`; it cannot prevent copies, and complete memory erasure is
  not verified.
- **Share custody** — `putShare` checks share kind and presence of threshold
  metadata. It does not validate share mathematics or a complete ceremony.
- **Evidence-oriented claims** — see [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md).

## Quick Start

The public constructor accepts `backend:` and `crypto:`. This in-memory sample
uses test-only bytes; do not substitute production key material or treat this
snippet as a complete application key-generation/passphrase policy. The example
app is still simulated; see TRK-013 in [`doc/TRACKER.md`](doc/TRACKER.md).

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:pqkeystore/pqkeystore.dart';

final crypto = PqForgeKeystoreCrypto();
final backend = MemoryKeystoreBackend();
final keystore = PqKeystore(backend: backend, crypto: crypto);

final metadata = KeyMetadata(
  id: KeyId('my-ml-kem-key'),
  kind: KeyKind.mlKemSecret,
  algorithm: 'ML-KEM-768',
  createdAt: DateTime.now(),
);

// These bytes and passphrase are for a local demonstration only.
final passphrase = Uint8List.fromList(utf8.encode('test-only-passphrase'));
final testKeyMaterial = Uint8List.fromList(List.generate(32, (index) => index));
await keystore.put(
  metadata,
  testKeyMaterial,
  PassphraseUnlock(passphrase),
);

// The callback copy is cleared after completion; complete memory erasure is
// not guaranteed.
final result = await keystore.use(
  KeyId('my-ml-kem-key'),
  PassphraseUnlock(passphrase),
  (plaintext) async => plaintext.length,
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
| **swissarmyknife** | Declared utility dependency; the facade currently exposes local `KsResult` types |

## Platform Support

All five targets implement [platform channel contract v1](doc/PLATFORM_CONTRACT.md). Support is claimed only once a platform's CI contract job passes; see [`doc/PLATFORM.md`](doc/PLATFORM.md).

| Platform | Mechanism | Status |
|----------|-----------|--------|
| Android | AndroidKeyStore AES-256-GCM, files in `noBackupFilesDir` | Implemented; pending CI |
| iOS | Data protection keychain | Implemented; pending CI |
| macOS | Data protection keychain (needs `keychain-access-groups`) | Implemented; pending CI and signing |
| Windows | DPAPI user-scope files | Implemented; pending CI |
| Linux | Secret Service via libsecret, no file fallback | Contract suite passing locally |

Unsupported storage options are rejected with `UNSUPPORTED_OPTION`, never ignored.
When the OS secure store is unavailable, an opt-in `FallbackKeystoreBackend` can persist sealed records into a private directory ([`doc/PLATFORM.md`](doc/PLATFORM.md)).

Byte-level layouts for every on-disk artifact: [`doc/FORMATS.md`](doc/FORMATS.md).

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

PQKS is not pqforge's `.pqf` one-shot or `.pqfs` streaming content envelope.
PQKS stores key metadata and the selected wrapper fields; this package currently
maps pqforge `PqWrappedKey` fields into PQKS. The content envelopes use a
recipient-oriented KEM model and are not used as keystore records. See
[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) and
[ADR-0007](doc/adr/0007-pqks-and-pqforge-format-boundaries.md).

## Documentation

- [`doc/INDEX.md`](doc/INDEX.md) — Documentation index
- [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) — System architecture
- [`doc/API.md`](doc/API.md) — API reference
- [`doc/PLATFORM.md`](doc/PLATFORM.md) — Platform support details
- [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) — Security claims & boundaries
- [`doc/TRACKER.md`](doc/TRACKER.md) — Production readiness work and release gates
- [`doc/BUGS.md`](doc/BUGS.md) — Confirmed defects from the source audit
- [ADRs](doc/adr/0001-five-platform-v1.md) — Architecture decisions and open choices
- [`AGENTS.md`](AGENTS.md) — Agent rules & conventions
- [`CONTINUE.md`](CONTINUE.md) — Next steps & continuation tasks
- [`SECURITY.md`](SECURITY.md) — Security policy

## License

MIT — Copyright 2024–2026 Yardenah PQ / Turkana Nation.
