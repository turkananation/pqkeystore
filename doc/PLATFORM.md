# Platform Support Matrix

`pqkeystore` relies on a consistent interface across all supported platforms to ensure predictable behavior and security.

## MethodChannel Details

* **Name**: `com.yardenah.pqkeystore/store`
* **Methods**:
  * `put`: Store a byte array against an ID.
  * `get`: Retrieve a byte array by ID.
  * `delete`: Remove an ID.
  * `contains`: Check if an ID exists.
  * `putJson`: Store metadata/indexes (optional, depending on backend impl).
  * `getJson`: Retrieve metadata/indexes.
  * `platformInfo`: Get OS capabilities.
* **Error Codes**: `NOT_FOUND`, `USER_CANCELLED`, `AUTH_FAILED`, `KEYSTORE_ERROR`, `UNSUPPORTED`, `INVALID_ARGS`.

## OS-Specific Implementations

Strict parity must be maintained across these implementations. The native code should act as a dumb storage layer, trusting the Dart side to handle encryption (PQKS).

| Platform | Underlying Technology | Details |
| :--- | :--- | :--- |
| **Android** | Android Keystore + SharedPreferences | Generates an AES-GCM key in the hardware Keystore. Uses this key to encrypt the PQKS blob, storing the resulting ciphertext in SharedPreferences or EncryptedSharedPreferences. |
| **iOS** | Keychain | Uses standard Keychain Services. Items are stored as generic passwords. The `kSecAttrAccessible` must be set to restrict access (e.g., `WhenUnlockedThisDeviceOnly`). |
| **macOS** | Keychain | Identical implementation to iOS, ensuring parity across Apple ecosystems. |
| **Windows** | DPAPI | Uses `CryptProtectData` with the `CRYPTPROTECT_UI_FORBIDDEN` flag. The resulting opaque blob is stored in a file within the user's `LOCALAPPDATA` directory. |
| **Linux** | Secret Service API / XDG | Prefers DBus Secret Service API (via `libsecret` or similar). If unavailable, falls back to storing the PQKS blob in a plain file within `$XDG_DATA_HOME` with strict `0600` permissions. |
