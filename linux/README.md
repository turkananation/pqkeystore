# pqkeystore — Linux

Implements [platform channel contract v1](../doc/PLATFORM_CONTRACT.md) on the
freedesktop Secret Service via libsecret. Design and limits: [ADR-0009](../doc/adr/0009-native-backend-designs.md).

| File | Role |
| --- | --- |
| `pq_keystore_plugin.cc` | Channel wiring; main-thread validation, exclusive worker thread |
| `pq_keystore_contract.{h,cc}` | Argument validation (unit-tested, no D-Bus) |
| `pq_keystore_secret_store.{h,cc}` | libsecret storage |
| `test/pq_keystore_contract_test.cc` | Native unit tests |

- Build dependency: `libsecret-1-dev` (Debian/Ubuntu) / `libsecret-devel` (Fedora), ≥ 0.18.
- **No file fallback**: without a reachable Secret Service every operation returns `UNAVAILABLE`.
- No optional capabilities are supported; all are rejected with `UNSUPPORTED_OPTION`.
- The Secret Service does not isolate applications: any process in the user session can read these items.

Native unit tests (from `example/` after `flutter build linux --debug`):

```sh
cmake --build build/linux/x64/debug --target pqkeystore_test
build/linux/x64/debug/plugins/pqkeystore/pqkeystore_test
```
