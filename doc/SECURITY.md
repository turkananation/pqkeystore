# Security Model

This document describes the threat model to use when evaluating `pqkeystore`; it does not assert that current platform implementations meet it. See [`CLAIM_BOUNDARY.md`](CLAIM_BOUNDARY.md) for current claims and [`TRACKER.md`](TRACKER.md) for release gates.

## Threat Model

We consider the following adversaries and capabilities:

1. **Passive Storage Access**: An attacker acquires stored application data.
    * *Intended mitigation*: Wrap key material before persistence. Actual protection depends on the selected crypto adapter, unlock mode, and backend; current native support is incomplete.
2. **App Compromise (Non-Root)**: Malware with access to the app process or its files attempts to read records or plaintext.
    * *Boundary*: This package does not prevent compromise of the application process. Platform isolation and access-control policies require implementation and verification on each OS.
3. **Rooted/Jailbroken Device**: An attacker has elevated privileges and can read any file or query the OS keystore directly.
    * *Boundary*: No protection against a compromised OS is claimed. Do not assume a specific algorithm, hardware-backed key, or passphrase flow without verifying the configured adapter and platform.
4. **Memory Scraping**: An attacker dumps the application's RAM to find keys.
    * *Boundary*: `use` limits the intended access scope and clears a callback copy, but the caller may retain copies and complete process-memory erasure is not established.

## Trust Boundaries

* **App <-> Keystore**: The caller controls key inputs and may copy or retain callback plaintext. The facade does not prevent this.
* **Keystore <-> Crypto Provider**: `pqkeystore` completely trusts `PqKeystoreCrypto` (e.g., `pqforge`) to execute cryptographic primitives correctly and securely.
* **Keystore <-> OS**: Native backends store opaque PQKS blobs and enforce or explicitly reject each storage option ([`PLATFORM_CONTRACT.md`](PLATFORM_CONTRACT.md)). Linux Secret Service and Windows DPAPI protect at the user-account level only: other processes running as the same user are not excluded.

## Defense in Depth

Our core philosophy is that no single layer should be relied upon exclusively:

1. **Transient Memory**: `use` is the preferred access pattern; copies and full erasure are not controlled.
2. **Inner Cryptography**: The crypto adapter is responsible for wrapping; the insecure stub must never be used with real secrets.
3. **Outer Storage**: Platform storage is a goal, not a verified guarantee across registered targets.
4. **Threshold Custody**: Share helper APIs exist, but they do not validate share mathematics or prove end-to-end threshold security.
