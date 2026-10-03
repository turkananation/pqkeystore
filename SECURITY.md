# Security Policy

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

If you believe you have found a security vulnerability in `pqkeystore`, please report it to us via email at [security@yardenah.com](mailto:security@yardenah.com). We will acknowledge receipt of your vulnerability report within 48 hours and strive to send you regular updates about our progress. If you're curious about the status of your report, feel free to email us again.

## Security Model Overview

The `pqkeystore` package employs a defense-in-depth strategy for key custody:

1. **Inner Protection (PQKS Inner Wrap):** Keys are serialized and encrypted using robust post-quantum or hybrid cryptographic mechanisms before they are written to disk. This ensures that even if the storage medium is compromised, the keys remain secure without the proper decryption material (e.g., a master password, biometrics, or hardware-backed root key).
2. **Outer Protection (OS-Level Isolation):** The encrypted keystore payloads are delegated to the operating system's native secure storage facilities (e.g., Android Keystore, iOS Keychain, Windows Credential Locker, Linux Secret Service / KWallet). This leverages platform-specific hardware security modules (HSMs) and secure enclaves (TEE) to protect the encryption keys used for the inner wrap.

## Critical Warnings

*   **`StubKeystoreCrypto` Is Not Secure:** The `StubKeystoreCrypto` implementation provided in this package is intended strictly for testing and development purposes. It provides **NO SECURITY GUARANTEES**. It must **NEVER** be shipped in a production environment. Always inject a real, cryptographically sound implementation (like `PqForgeKeystoreCrypto`) when deploying.
*   **Secrets in Logs:** The `pqkeystore` package is designed to never print cryptographic keys, passwords, or sensitive material to standard output, logs, or error messages. If you discover a case where sensitive information is leaked in this manner, treat it as a critical security vulnerability and report it immediately.
*   **Keystore Files (`.pqks`):** You must never commit `.pqks` files to version control. Our `.gitignore` explicitly prevents this.
