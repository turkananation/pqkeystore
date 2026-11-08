# Provider lifecycle evidence (TRK-005)

This is the dependency-level ownership record for the pinned adapter. It is not a claim of complete memory erasure, and it is not an independent review.

Reviewed against source, not against a guess:

| Package | Constraint | Source reviewed |
| --- | --- | --- |
| `pqforge` | `^0.4.13` | tag `v0.4.13` (`b1d6e6a4`), compared with tag `v0.4.7` (`7e59082b`). `PqExportedKey` still copies on construction (`lib/src/keys/pq_keys.dart`, `_copy`). `wrapKeyWithPassphrase` / `unwrapKeyWithPassphrase` are still synchronous and still take a `String` passphrase (`lib/src/services/pqforge_service.dart`). Argon2id bounds are unchanged: iterations 1..10, `memoryPowerOf2` 10..20, lanes 1..16, salt ≥ 8. `argon2id` still does `utf8.encode(password)`. |
| `zeroize` | `^0.2.0` | tag `v0.2.0` (`d9540db2`). `SecretBytes.fromUint8List` always copies and never takes ownership (`lib/src/containers/secret_bytes.dart`). `dispose` wipes that copy. `secureZero` is the wipe that survives DSE. |

The two tags agree on the copy and the Argon2 window. This package's salt floor is **16**, stricter than pqforge's 8, because that is the salt `PqForgeKeystoreCrypto` writes.

## Passphrase encoding (v1 wire contract)

`PassphraseUnlock.passphrase` is a `Uint8List`. The adapter passes `String.fromCharCodes` of those bytes into pqforge, and pqforge UTF-8-encodes that string before Argon2id. Bytes `0x00..0x7F` are unchanged. Bytes `0x80..0xFF` expand to two UTF-8 bytes. This is not a raw-octet KDF input. Both wrap and unwrap use the same path, so a high byte still round-trips (`test/provider_lifecycle_test.dart`). The `String` cannot be overwritten. That remains a non-claim.

## Unlock modes

| Type | v1 behavior |
| --- | --- |
| `PassphraseUnlock` | The only accepted inner unwrap. Empty passphrase is `CryptoError`. |
| `PlatformUnlock` | `PolicyError` at the facade, before wrap or unwrap. Not an inner KDF factor. |
| `PassphraseThenPlatform` | `PolicyError`. It is **not** treated as passphrase-only. A real second factor is future work (ADR-0004). |

## Buffers this package can see

| Buffer | Who allocates it | Wiped by this package? |
| --- | --- | --- |
| Caller plaintext passed to `put` | Caller | No. It is not owned here. `provider_lifecycle_test.dart` asserts the caller's bytes survive `put`. |
| `SecretBytes` copy of that plaintext, and of the passphrase | `SecretBytes.fromUint8List` | Yes. `dispose()` in `finally`, including when wrap throws. |
| `Uint8List.fromList` export copy inside `wrap` | This package | Yes. `secureZero` in `finally`, then the assert-gated `debugAfterPlaintextWipe` hook. The test requires two wiped instances. |
| `PqExportedKey.bytes` | pqforge's constructor copy | Yes, after synchronous `wrapKeyWithPassphrase` returns. Same hook. |
| Passphrase `String` | `String.fromCharCodes` | No. Immutable. Non-claim. |
| Argon2id / AES temporaries inside pqforge | pqforge | No. Not reachable. Non-claim. |
| Decrypt output before `PqExportedKey` copies it | pqforge | No. Not reachable. Non-claim. |
| `PqExportedKey.bytes` returned by `unwrapKeyWithPassphrase` | pqforge, returned to us | Yes. The facade treats it as the unwrap buffer: copy into `SecretBytes`, `secureZero` the source immediately, wipe the callback copy in `finally`. Evidence: `test/secret_lifetime_test.dart`. |
| Callback's own copies | The callback | No. Non-claim. |
| GC-moved copies, swap, core dumps | The runtime / OS | No. Non-claim. |

`debugAfterPlaintextWipe` runs only inside `assert`, after the wipe. Release builds do not call it. It is not a way to read a live secret.

## KDF costs

Stored `kdfParams` are attacker-controlled. `validateStoredArgon2idParams` runs in the facade **before** `unwrap`, and again at the top of `PqForgeKeystoreCrypto.unwrap` before `PqWrappedKey` is built. Out of range is `FormatError` naming the parameter, the observed value, and the permitted range — never `CryptoError`. v1 permits only `kdf = argon2id` and `aead = aes-256-gcm`. A missing numeric field falls back to the adapter's in-range default; a present field of the wrong JSON type is rejected.

Chosen wrap costs (`PqForgeKeystoreCrypto(iterations:, memoryPowerOf2:, lanes:)`) use the same window and throw `ArgumentError` at construction. Defaults stay pqforge's 2 / 16 / 4.

Tests: `test/kdf_bounds_test.dart`, `test/provider_lifecycle_test.dart`.
