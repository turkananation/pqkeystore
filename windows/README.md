# pqkeystore — Windows

Native Windows implementation of
[platform channel contract v1](../doc/PLATFORM_CONTRACT.md) using
**DPAPI-protected files**. Design and limits:
[ADR-0009](../doc/adr/0009-native-backend-designs.md).

## Storage model

| Property | Value |
| --- | --- |
| Protection | `CryptProtectData` / `CryptUnprotectData` (DPAPI), **user scope** |
| Location | `%LOCALAPPDATA%\yardenah\pqkeystore\<exe-stem>\v1\` |
| File name | `hex(SHA-256(UTF-8 ID)).pqnw` |
| Envelope | PQKS record inside a PQNW container, DPAPI-protected |
| Entropy | `context ‖ 0x00 ‖ app ‖ 0x00 ‖ id`, binding each blob to its app namespace and ID |
| ACL on created directories | current user + SYSTEM only |
| Record size | 1 byte … 1 MiB |
| ID size | 1 … 256 UTF-8 bytes, no U+0000 |

The `<exe-stem>` component namespacing means two applications on the same
machine do not collide — but see *Isolation* below.

Native code stores **one opaque PQKS blob per ID and nothing else**. It never
parses metadata and reserves no ID prefix, so there is no `__meta__` namespace
and no sidecar record.

## The PQNW envelope

```
"PQNW" | u8 version | u16be idLen | id bytes | u32be blobLen | DPAPI blob
```

The blob is the PQKS record encrypted with `CryptProtectData` using
`CRYPTPROTECT_UI_FORBIDDEN` and entropy `com.yardenah.pqkeystore.v1\0app\0id`.
Because the ID is inside the entropy, a file cannot be moved to another ID's
name and still decrypt: the tag check fails and the entry is reported
`CORRUPT`, not silently returned.

Strict framing: a file with trailing bytes, a wrong magic, a wrong version or a
length that does not match the file size is rejected, never partially parsed.

## Durability

- Write path: unique temp file in the same directory → `FlushFileBuffers` →
  `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`, retrying transient sharing
  violations caused by antivirus scanners and indexers.
- The previous entry survives every failure before the rename, so a failed
  update cannot destroy the last valid record.
- Readers open with `FILE_SHARE_DELETE` so our own replacement is never blocked
  by a concurrent read.
- Stale temp files older than 10 minutes are reclaimed at startup.
- DPAPI itself adds a few hundred bytes of overhead; the reader allows generous
  headroom over the 1 MiB contract maximum.

## Capabilities

**None.** No optional security option is offered; all are rejected with
`UNSUPPORTED_OPTION`:

| Option | Status |
| --- | --- |
| `requireUserPresence` | unsupported |
| `requireBiometric` | unsupported |
| `accessibility.whenUnlocked` | unsupported |
| `accessibility.afterFirstUnlock` | unsupported |
| `synchronizable` | unsupported |

Windows Hello (`KeyCredentialManager`) is a candidate for a future
`requireUserPresence`, but it is not implemented and therefore not offered.

## Isolation — the honest limitation

DPAPI **user scope** means any process running as the same user can call
`CryptUnprotectData` on the blob. The executable-stem namespacing and the
restricted directory ACL raise the bar but do **not** provide per-application
isolation the way the Apple keychain or AndroidKeyStore UID scoping does.

`Doc/CLAIM_BOUNDARY.md` states this explicitly rather than implying parity
with the mobile platforms.

## Threading

`pq_keystore_plugin.cpp` handles calls on the platform thread, synchronously.
DPAPI file I/O for records up to 1 MiB is fast and, more importantly, keeping
the call on the platform thread avoids cross-thread ordering surprises with
`result->Success`.

## Source map

| File | Role |
| --- | --- |
| `pq_keystore_plugin_c_api.cpp` | `PqKeystorePluginCApiRegisterWithRegistrar` entry point |
| `pq_keystore_plugin.{h,cpp}` | Channel wiring, error mapping |
| `pq_keystore_contract.{h,cpp}` | Argument validation (portable C++, unit-tested) |
| `pq_keystore_dpapi_store.{h,cpp}` | PQNW envelope, DPAPI, atomic replace |
| `test/pq_keystore_plugin_test.cpp` | Native unit tests (validation + real DPAPI round trips) |

## Tests

Native unit tests, from `example/` after `flutter build windows --debug`:

```sh
cmake --build build/windows/x64 --config Debug --target pqkeystore_test
build/windows/x64/plugins/pqkeystore/Debug/pqkeystore_test.exe
```

End-to-end contract suite against the real plugin:

```sh
flutter test integration_test/platform_contract_test.dart -d windows
```

CI runs both ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml));
both are green.

## What is NOT claimed

- **Per-application isolation.** DPAPI user scope does not provide it.
- **Any capability flags.** All are refused with `UNSUPPORTED_OPTION`.
- **Hardware / TPM binding.** DPAPI user scope is not TPM-bound.
- **Post-erasure.** `delete` removes the file; it does not overwrite flash.
- **Roaming.** Records live in `%LOCALAPPDATA%` and do not roam to another
  machine.
