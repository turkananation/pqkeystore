# pqkeystore

**Custody, storage and lifecycle primitives for post-quantum key material.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0--dev.1-orange.svg)](https://github.com/turkananation/pqkeystore/releases)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.12-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.24-blue.svg)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%C2%B7%20iOS%20%C2%B7%20macOS%20%C2%B7%20Windows%20%C2%B7%20Linux-lightgrey.svg)](#platform-support)

---

## What this package is

A **keychain for keys you cannot re-derive**.

A post-quantum private key is not something you regenerate when you lose it,
and it is not something you want sitting in a config file, an environment
variable, or a heap buffer that nobody is tracking. `pqkeystore` takes raw key
bytes, seals them into a versioned, self-describing record, and hands that
record to the operating system's own protected storage: **AndroidKeyStore**,
the **Apple data protection keychain**, **Windows DPAPI**, or the **freedesktop
Secret Service**.

When you need the key, you get it through a scoped callback and it is wiped on
the way out. There is no `getKey()` that hands a caller an unmanaged buffer.

This package deliberately does **not** implement post-quantum mathematics. It
is custody only. Lattice primitives belong to `pqcrypto`, application-level
crypto to `pqforge`, threshold ceremony to `pqthreshold`.

## Status

This is a **development release** (`0.1.0-dev.1`, `publish_to: none`). It is
not audited and not claiming production security. What *is* backed by evidence:

| Area | State |
| --- | --- |
| Dart facade, PQKS codec, memory/file backends | Implemented, 135 passing tests |
| Five-platform channel contract v1 | Implemented on all five targets |
| On-device contract suite | **Green** on Android (API 26/28/35), Windows, Linux, iOS (SwiftPM) |
| macOS, iOS CocoaPods | Build; contract suite gated on an Apple signing identity |
| File store v1 | Hashed names, atomic replace, no index, verified permissions |
| Fallback store | Opt-in, tombstoned, migrate-on-write |
| Independent security review | **Not performed** — see [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) |

Every claim this project makes is recorded with its evidence in
[`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md), and every non-claim is
recorded next to it. Where a property is *not* proven — complete memory
erasure, hardware backing, per-application isolation — this README says so
rather than implying otherwise.

> [!CAUTION]
> **Not production-ready, and it tells you so.** `StubKeystoreCrypto` is
> **NOT SECURE** — it is an XOR stub for structural tests and must never touch
> real key material. `PqForgeKeystoreCrypto` is the real adapter. No
> independent security review has been performed.

---

## Quick start

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:pqkeystore/pqkeystore.dart';

final keystore = PqKeystore(
  backend: PlatformKeystoreBackend(),   // AndroidKeyStore / keychain / DPAPI / Secret Service
  crypto: PqForgeKeystoreCrypto(),       // real wrapping via pqforge
);

// Bytes and passphrase below are for demonstration only.
final passphrase = Uint8List.fromList(utf8.encode('correct-horse-battery-staple'));

await keystore.put(
  KeyMetadata(
    id: const KeyId('ml-kem-768/primary'),
    kind: KeyKind.mlKemSecret,
    algorithm: 'ML-KEM-768',
    createdAt: DateTime.now(),
    purpose: 'primary signing key',
  ),
  Uint8List.fromList(List.generate(1184, (i) => i)),  // your key bytes
  PassphraseUnlock(passphrase),
);

// Use it. The plaintext exists only inside this closure, and is wiped on exit.
final signature = await keystore.use(
  const KeyId('ml-kem-768/primary'),
  PassphraseUnlock(passphrase),
  (secret) async => signSomething(secret),
);

await keystore.delete(const KeyId('ml-kem-768/primary'));
```

`use()` is the API we want you to use. It refuses to touch the crypto adapter
unless the record's identity and canonical metadata AAD check out, and it wipes
every buffer it owns on **every** exit path — success, callback exception, or
rejection. See [Secret lifecycle](#secret-lifecycle).

---

## Why the design looks like this

### One opaque record per ID, and nothing else

Native code stores exactly one opaque byte string per key ID. It never parses
metadata, never reserves an ID prefix, and never keeps a sidecar record.

This is not an implementation detail — it removes whole classes of bugs:

- **No metadata/record split.** A record and its metadata can never disagree
  because there is only one thing to write. Each write is one atomic native
  operation, so "record written but metadata lost" is not a state the system
  can enter.
- **No reserved namespace.** An ID that *looks* like internal bookkeeping
  (`__meta__x`) is just an ordinary ID. There is nothing to collide with.
- **No ID-as-path.** Every backend maps an ID to a storage key through an
  injective, non-reversible transform.

### Validate before you decrypt

`use()` recomputes the canonical AAD from the record's decoded metadata and
refuses to call the crypto adapter unless the stored AAD matches, and unless
the decoded ID is the ID you asked for. A record whose metadata was edited
out-of-band fails closed — the tamper never reaches key-unwrapping code. This
is covered by per-field regression tests, not just a code comment.

### Fail loudly, never silently

- An unsupported security option is **rejected** with `UNSUPPORTED_OPTION`. It
  is never ignored.
- If the OS secure store is unreachable — no Secret Service on a headless box,
  no keychain entitlement on an unsigned build — operations fail with
  `UNAVAILABLE`. Linux in particular **never** falls back to a file on its own.
  Silently degrading a keychain is how real keys end up on disk.

### Opt-in fallback, when you really need it

If your threat model permits file storage and the OS store is unavailable, you
can ask for it explicitly:

```dart
final backend = FallbackKeystoreBackend(
  secure: PlatformKeystoreBackend(),
  fallback: FileKeystoreBackend(Directory('${dir.path}/pqkeystore')),
  onFallback: (reason) => log.warning('secrets are in the file fallback: $reason'),
);
```

It reads the fallback copy first (never older than the secure copy), removes
the fallback copy once a secure write succeeds, and leaves **tombstones** so a
record deleted while the store was down cannot resurface when it returns.

---

## Secret lifecycle

Zeroization is a cardinal project rule ([`AGENTS.md` rule 10](AGENTS.md)), not
an afterthought, because the obvious approach is quietly wrong:

> `SecretBytes.fromUint8List(buffer)` **always copies and never takes
> ownership**. Disposing the copy does *not* wipe your original buffer — it
> stays live in the heap until the garbage collector reclaims it, where swap,
> core dumps and post-mortem debugging can still read it.

So `use()` owns the buffer its crypto adapter returns, copies it, and wipes
the source with `secureZero` immediately:

```dart
final SecretBytes owned;
try {
  owned = SecretBytes.fromUint8List(plaintext);  // copy
} finally {
  secureZero(plaintext);                         // source wiped, even if the copy throws
}
```

`secureZero` is used rather than a hand-written loop because it is
`@pragma('vm:never-inline')` with opaque read anchors, so it survives Dead
Store Elimination in AOT builds. Every plaintext-handling site must ship a
regression test that **fails when the wipe is removed** — see
[`test/secret_lifetime_test.dart`](test/secret_lifetime_test.dart), which
captures the exact buffer instance handed to the facade and asserts it is
zero afterwards.

**What we still do not claim:** the Dart GC can copy a buffer before we zero it;
the passphrase is converted to an immutable `String` inside the adapter; buffers
allocated inside `pqforge` are not ours to wipe; and pure Dart cannot `mlock`.
Those are named non-claims, not oversights.

---

## Platform support

All five targets implement
[platform channel contract v1](doc/PLATFORM_CONTRACT.md) — one channel name
(`com.yardenah.pqkeystore/store`), one method schema, one set of error codes,
one shared conformance suite.

| Platform | Mechanism | Contract suite | Details |
| --- | --- | --- | --- |
| **Android** | AndroidKeyStore AES-256-GCM, `noBackupFilesDir`, PQNA v2 | ✅ API 26 / 28 / 35 | [`android/README.md`](android/README.md) |
| **Windows** | DPAPI user scope, `%LOCALAPPDATA%`, PQNW | ✅ | [`windows/README.md`](windows/README.md) |
| **Linux** | Secret Service via libsecret, **no file fallback** | ✅ | [`linux/README.md`](linux/README.md) |
| **iOS** | Data protection keychain (shared Darwin source) | ✅ SwiftPM · ⛔ CocoaPods¹ | [`darwin/README.md`](darwin/README.md) |
| **macOS** | Data protection keychain (needs `keychain-access-groups`) | ⛔¹ | [`darwin/README.md`](darwin/README.md) |

¹ The macOS and iOS-CocoaPods jobs build successfully and then **fail fast
with an explicit "no Apple development signing identity" error**. That is
intentional: the data protection keychain requires a team-signed build, and a
loud failure is better than a mysterious launch timeout. Provision
`DEVELOPMENT_TEAM` in CI and no code change is needed.

Capability flags differ per platform and are reported dynamically in
`platformInfo.supportedOptions`. Options a device cannot enforce are refused
with `UNSUPPORTED_OPTION` — Android, Windows and Linux currently offer **none**;
Darwin offers user presence, biometrics, accessibility class and
synchronization where the OS supports them.

Byte-level layouts for every on-disk artifact — PQKS, PQNA, PQNW, the keychain
item, the Secret Service item, file store v1, tombstones:
[`doc/FORMATS.md`](doc/FORMATS.md).

---

## Architecture

```text
┌────────────────────────────────────────────────────────┐
│                     Application                        │
├────────────────────────────────────────────────────────┤
│                    PqKeystore                          │
│   put · use · delete · list · metadata                │
│   putShare · useShare                                  │
│   ┌──────────────────────────────────────────────┐     │
│   │ validate identity + canonical AAD            │     │
│   │ wipe every buffer it owns on every exit      │     │
│   └──────────────────────────────────────────────┘     │
├─────────────────────────┬──────────────────────────────┤
│    PqKeystoreCrypto     │       PqKeystoreBackend      │
│      wrap / unwrap      │  Memory │ File │ Platform    │
│                         │       │         │            │
│  PqForgeKeystoreCrypto  │         │    Fallback (opt-in)│
│  StubKeystoreCrypto     │         │         │          │
│  ⚠ NOT SECURE           │         │         │          │
├─────────────────────────┴──────────────────────────────┤
│      Native storage — one opaque PQKS blob per ID       │
│  AndroidKeyStore · Apple keychain · DPAPI · Secret Svc │
└────────────────────────────────────────────────────────┘
```

Key source locations:

| Path | Contents |
| --- | --- |
| `lib/src/api/` | Facade, record codec, metadata, errors, unlock types |
| `lib/src/backend/` | Memory, file, platform and fallback backends |
| `lib/src/crypto/` | `PqKeystoreCrypto` contract and implementations |
| `lib/pqkeystore.dart` | Public barrel — import only this |
| `test/` | Unit, contract and security-regression suites |
| `tool/verify.sh` | Pure-Dart verification gate (no device needed) |

---

## PQKS: the portable record

Every sealed record uses one wire format, so records stay meaningful across
backends and platforms:

| Field | Encoding |
| --- | --- |
| Magic | `0x50 0x51 0x4B 0x53` (`PQKS`) |
| Version | uint32 BE |
| `wrapAlg` | length-prefixed UTF-8 |
| `metadata` | length-prefixed JSON UTF-8 (cleartext — see non-claims) |
| `aad` | length-prefixed bytes |
| `nonce` | length-prefixed bytes |
| `kdfParams` | length-prefixed JSON UTF-8 |
| `ciphertext` | length-prefixed bytes |

Decoding is strict: trailing bytes, truncation, unsupported versions and
absurd declared field lengths are all rejected with a controlled error rather
than partially parsed.

PQKS is **not** pqforge's `.pqf` one-shot or `.pqfs` streaming content
envelope. Those are recipient-oriented content envelopes; PQKS is a keystore
record. See [ADR-0007](doc/adr/0007-pqks-and-pqforge-format-boundaries.md).

---

## The Yardenah post-quantum stack

| Package | Role |
| --- | --- |
| **pqcrypto** | ML-KEM / ML-DSA / SLH-DSA primitives |
| **pqforge** | Application crypto, hybrids, envelopes, wrap/unwrap |
| **pqkeystore** | **Key custody & lifecycle (this package)** |
| **pqthreshold** | VSS, DKG, FROST — threshold ceremony |
| **pqdga** | Deterministic namespace / rendezvous material |
| **pqtransport** | Transport-layer key management |
| **zeroize** | Secret lifecycle, multi-pass zeroing, `SecretBytes` |

---

## Testing

The whole package is testable in pure Dart — no device, no emulator:

```sh
tool/verify.sh              # root + example: pub get, analyze, test
flutter test                 # 135 tests
cd example/android && ./gradlew :pqkeystore:testDebugUnitTest
```

The same conformance suite runs against every real native implementation:

```sh
flutter test integration_test/platform_contract_test.dart -d <device>
```

CI (`.github/workflows/ci.yml`) runs the Dart gate plus native builds and
contract suites for all five platforms on every push and pull request. A
platform that cannot be verified fails visibly — it is never counted as
coverage. See [`doc/TRACKER.md`](doc/TRACKER.md) for the live gate status.

---

## Documentation

| Document | Purpose |
| --- | --- |
| [`doc/INDEX.md`](doc/INDEX.md) | Documentation index |
| [`doc/API.md`](doc/API.md) | API reference |
| [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) | System architecture |
| [`doc/FORMATS.md`](doc/FORMATS.md) | Every on-disk byte layout |
| [`doc/PLATFORM_CONTRACT.md`](doc/PLATFORM_CONTRACT.md) | The native channel contract |
| [`doc/PLATFORM.md`](doc/PLATFORM.md) | Platform support matrix and setup |
| [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) | **What is claimed, what is not, and why** |
| [`doc/TRACKER.md`](doc/TRACKER.md) | Production-readiness gates |
| [`doc/BUGS.md`](doc/BUGS.md) | Confirmed defects and their fixes |
| [`doc/adr/`](doc/adr/) | Architecture decision records |
| [`AGENTS.md`](AGENTS.md) | Hard rules for contributors and agents |
| [`SECURITY.md`](SECURITY.md) | Security policy |

Platform-specific storage, capabilities and non-claims:
[`android/`](android/README.md) · [`darwin/`](darwin/README.md) ·
[`windows/`](windows/README.md) · [`linux/`](linux/README.md)

---

## License

MIT — Copyright 2024–2026 Yardenah PQ / Turkana Nation.
