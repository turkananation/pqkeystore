# Windows C API Scaffold for PQ Keystore

This directory contains the scaffolding for the Windows implementation of the `pqkeystore` Flutter plugin.

## Implementation Details

The implementation should use the Data Protection API (DPAPI) to securely store and retrieve encrypted data.

- **Storage**: Data should be stored as encrypted files in `%LOCALAPPDATA%\yardenah\pqkeystore\`.
- **Encryption**: Use `CryptProtectData` to encrypt data before writing to the file system. Ensure the `CRYPTPROTECT_UI_FORBIDDEN` flag is set to prevent any UI prompts from blocking the application.
- **Decryption**: Use `CryptUnprotectData` to decrypt data retrieved from the file system.
- **Methods**: Implement the following C API endpoints exposed via `pq_keystore_plugin_c_api.cpp`:
    - `put`
    - `get`
    - `delete`
    - `contains`
    - `putJson`
    - `getJson`
    - `platformInfo`

This remains a TODO for complete integration.
