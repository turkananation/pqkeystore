# Platform Support Matrix

All five registered targets are required for v1, but registration is not evidence of working storage. Current native code has contract mismatches or stubs. None of the platform implementations is considered production-ready from the source audit. See [`TRACKER.md`](TRACKER.md) and [ADR-0001](adr/0001-five-platform-v1.md).

## Current Status

| Platform | Source status | Production status |
| :--- | :--- | :--- |
| Android | Partial native handler; contract mismatch with Dart. Listing is incomplete. | Not ready |
| iOS | Partial Keychain handler; contract mismatch with Dart. Listing is incomplete. | Not ready |
| macOS | Partial Keychain handler; contract mismatch with Dart. Listing is incomplete. | Not ready |
| Windows | Registered plugin source is a stub without the required method implementation. | Not implemented |
| Linux | Registered plugin source is a stub without the required method implementation. | Not implemented |

Specific hardware backing, user-presence enforcement, biometrics, filesystem permissions, and platform build status have not been verified. The package's option types must not be interpreted as guarantees that native code applies those policies.

## Dart Channel Client And Contract Gap

The channel name in the Dart client is `com.yardenah.pqkeystore/store`. The Dart client calls `put`, `get`, `delete`, `contains`, `putJson`, `getJson`, `listIds`, and `platformInfo`. Current Dart calls use `id` and `data`; existing Android and Apple handlers expect `key` and `value`. The client expects a boolean delete result, but native handlers do not consistently return one. `listIds` is not implemented by Android or Apple. This makes the current client/native contract incompatible; see BUG-002 through BUG-004 in [`BUGS.md`](BUGS.md).

The canonical argument/result and error contract is not yet accepted. [ADR-0002](adr/0002-platform-channel-contract.md) records the decision needed before native parity work. Do not treat the method list above as a guarantee of support. Confirmed contract defects are in [`BUGS.md`](BUGS.md).

## v1 Acceptance Bar

Each platform must build in CI and pass shared tests for CRUD, contains, list/filter, metadata, not-found behavior, error mapping, and option handling. Unsupported security options must fail explicitly. Platform-specific implementation details are allowed only behind equivalent observable behavior.
