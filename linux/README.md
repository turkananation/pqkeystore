# Linux C++ Scaffold for PQ Keystore

This directory contains the scaffolding for the Linux implementation of the `pqkeystore` Flutter plugin.

## Implementation Details

The implementation should integrate with `libsecret` to securely store and retrieve data.

- **libsecret Integration**: Use the standard D-Bus Secret Service API via `libsecret`.
- **File Fallback**: In environments without a secret service, gracefully fallback to storing encrypted files in XDG directories (`$XDG_DATA_HOME/yardenah/pqkeystore` or `~/.local/share/yardenah/pqkeystore`). Ensure fallback files have strictly controlled permissions (chmod `0600`).
- **Methods**: Implement the necessary functionality in `pq_keystore_plugin.cc` and register the Flutter method channel correctly.

This remains a TODO for complete integration.
