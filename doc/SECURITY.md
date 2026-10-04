# Security Model

The `pqkeystore` security model is designed to mitigate risks in hostile execution environments (e.g., mobile devices, user desktops) by employing a defense-in-depth approach.

## Threat Model

We consider the following adversaries and capabilities:

1. **Passive Storage Access**: An attacker acquires the physical device or a backup of the device's storage.
    * *Mitigation*: OS-level secure storage (Keychain/Keystore) prevents extraction without device unlocking. The inner PQKS wrap requires a user passphrase, adding a second factor.
2. **App Compromise (Non-Root)**: Malware on the same device attempts to access the keystore files.
    * *Mitigation*: OS sandboxing prevents access to other apps' data. DPAPI/Keychain policies prevent unauthorized processes from requesting the data.
3. **Rooted/Jailbroken Device**: An attacker has elevated privileges and can read any file or query the OS keystore directly.
    * *Mitigation*: The OS layer is bypassed. The attacker obtains the PQKS blob. The inner encryption (AES/Kyber via `pqforge`) bound to a user passphrase is the final line of defense.
4. **Memory Scraping**: An attacker dumps the application's RAM to find keys.
    * *Mitigation*: The `PqKeystore.use()` API combined with `zeroize` ensures keys exist in plaintext for the absolute minimum time required.

## Trust Boundaries

* **App <-> Keystore**: The app trusts `pqkeystore` to store and retrieve data faithfully. `pqkeystore` trusts the app not to leak the plaintext buffer provided during the `use()` callback.
* **Keystore <-> Crypto Provider**: `pqkeystore` completely trusts `PqKeystoreCrypto` (e.g., `pqforge`) to execute cryptographic primitives correctly and securely.
* **Keystore <-> OS**: `pqkeystore` trusts the operating system to enforce its stated security policies (sandboxing, keychain access control).

## Defense in Depth

Our core philosophy is that no single layer should be relied upon exclusively:

1. **Transient Memory**: Keys are never held in state.
2. **Inner Cryptography**: The payload is always encrypted by our own code before touching disk.
3. **Outer Cryptography**: The encrypted payload is handed to the OS for its own storage encryption.
4. **Threshold Cryptography**: By storing only shares, a complete device compromise only yields a fraction of the key.
