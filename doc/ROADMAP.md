# Roadmap

This document outlines the planned development phases for `pqkeystore`.

## Phase 0.1.0-dev: Scaffold & Structure (Current)
*   Define interfaces (`PqKeystore`, `Backend`, `Crypto`).
*   Establish strict Agent guidelines and documentation.
*   Implement `MemoryKeystoreBackend` and `FileKeystoreBackend` (basic).
*   Create `StubKeystoreCrypto` for CI structural testing.
*   *Goal: Architecture validated, tests passing, ready for real crypto.*

## Phase 0.1.0: Cryptographic Integration
*   Wire in `pqforge` for AEAD and key derivation.
*   Implement real `PqForgeKeystoreCrypto` replacing the stub.
*   Integrate `zeroize` for memory safety.
*   Integrate `swissarmyknife` `Result` types.
*   *Goal: Secure pure-Dart implementation ready.*

## Phase 0.2.0: Native Platform Backends
*   Implement Android MethodChannel (Keystore).
*   Implement iOS/macOS MethodChannel (Keychain).
*   Implement Windows MethodChannel (DPAPI).
*   Implement Linux MethodChannel (Secret Service/XDG).
*   *Goal: Hardware/OS-backed storage operational on all platforms.*

## Phase 0.3.0: Threshold & Ecosystem
*   Finalize `putShare` / `useShare` workflows.
*   Integration testing with `pqthreshold`.
*   Cross-platform round-trip testing (ensuring a blob generated on Android can be parsed conceptually, though OS boundaries prevent direct sharing).
*   *Goal: Fully integrated into the Yardenah ecosystem.*

## Phase 1.0.0: Stable Release
*   Comprehensive external security audit.
*   Final review against `CLAIM_BOUNDARY.md`.
*   API stabilization.
*   *Goal: Production-ready release.*
