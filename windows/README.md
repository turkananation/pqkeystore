# pqkeystore — Windows

Implements [platform channel contract v1](../doc/PLATFORM_CONTRACT.md) with
DPAPI-protected files. Design and limits: [ADR-0009](../doc/adr/0009-native-backend-designs.md).

| File | Role |
| --- | --- |
| `pq_keystore_plugin_c_api.cpp` | `PqKeystorePluginCApiRegisterWithRegistrar` entry point |
| `pq_keystore_plugin.{h,cpp}` | Channel wiring (platform thread, synchronous) |
| `pq_keystore_contract.{h,cpp}` | Argument validation (portable C++, unit-tested) |
| `pq_keystore_dpapi_store.{h,cpp}` | DPAPI file store |
| `test/pq_keystore_plugin_test.cpp` | Native unit tests (validation + real DPAPI round trips) |

- Location: `%LOCALAPPDATA%\yardenah\pqkeystore\<exe-stem>\v1\`. Directories the plugin creates are restricted to the current user and SYSTEM.
- File names are `sha256(id).pqnw` (PQNW envelope, see [`doc/FORMATS.md`](../doc/FORMATS.md)). The ID is stored in the header and bound into the DPAPI entropy.
- Writes are atomic (`MoveFileExW` replace). Old entries survive failed writes.
- No optional capabilities in v1; all are rejected with `UNSUPPORTED_OPTION`.
- DPAPI user scope does not isolate applications running as the same user.

Native unit tests (from `example/` after `flutter build windows --debug`):

```sh
cmake --build build/windows/x64 --config Debug --target pqkeystore_test
build/windows/x64/plugins/pqkeystore/Debug/pqkeystore_test.exe
```
