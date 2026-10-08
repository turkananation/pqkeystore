# Security Policy

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

If you believe you have found a security vulnerability in `pqkeystore`, please report it to us via email at [security@yardenah.com](mailto:security@yardenah.com). We will acknowledge receipt of your vulnerability report within 48 hours and strive to send you regular updates about our progress. If you're curious about the status of your report, feel free to email us again.

## Security Model Overview

The package is not currently production-ready. A `PqForgeKeystoreCrypto` adapter exists, but its provider security properties and the complete platform storage system are not independently verified. Native backends implement platform channel contract v1 on all five targets, but only Linux has on-device evidence so far (see `doc/PLATFORM.md`). Do not assume biometric enforcement, hardware backing, or cross-platform OS isolation.

See [`doc/CLAIM_BOUNDARY.md`](doc/CLAIM_BOUNDARY.md) for current claims and non-claims and [`doc/TRACKER.md`](doc/TRACKER.md) for release gates. The stub crypto implementation provides no security and must never be used with real key material.

## Critical Warnings

* **`StubKeystoreCrypto` Is Not Secure:** The stub is for structural tests only and provides **NO SECURITY GUARANTEES**. Never use it with real secrets. Presence of `PqForgeKeystoreCrypto` does not itself establish production readiness.
* **Secrets in Logs:** The package must never print cryptographic keys, passwords, or sensitive material to standard output, logs, or error messages. Report any leakage as a security vulnerability.
* **Keystore Files (`.pqks`):** Never commit `.pqks` files containing real key material, passphrases, or shares to version control.
