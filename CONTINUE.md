# Next Steps (CONTINUE)

To resume work on `pqkeystore`, begin by running the verification suite to ensure the baseline is stable:

```bash
cd pqkeystore && flutter pub get && dart analyze && flutter test
```

## Ordered Continuation Tasks

The following tasks are prioritized for the next phase of development.

> **[!IMPORTANT]**
> **Top 3 Immediate Tasks:**
>
> 1. Wire `pqforge` + `zeroize`; implement real `PqForgeKeystoreCrypto`.
> 2. Wire `swissarmyknife` `Result` replacing local `KsResult`.
> 3. Harden `FileKeystoreBackend` + sealed index.

### Full Task List

1. **Wire `pqforge` + `zeroize`; implement real `PqForgeKeystoreCrypto`**
    * Replace `StubKeystoreCrypto` with a robust implementation leveraging `pqforge` for AEAD wrapping and `zeroize` for immediate memory clearing of plaintext buffers.
2. **Wire `swissarmyknife` `Result` replacing local `KsResult`**
    * Deprecate any local `KsResult` or exception-heavy flows in favor of the standardized functional `Result` type from the `swissarmyknife` package.
3. **Harden `FileKeystoreBackend` + sealed index**
    * Ensure the file backend uses atomic writes. Implement a sealed, integrity-checked index so the application knows which keys exist without scanning the filesystem.
4. **Platform round-trips: Android -> iOS/macOS -> Windows -> Linux**
    * Implement the native code for the `MethodChannelBackend` on all five supported platforms, ensuring strict parity in method signatures and error codes.
5. **Threshold validation with `pqthreshold`**
    * Implement and test the `putShare` and `useShare` workflows. Integrate with `pqthreshold` to validate that shares can be safely utilized without full reconstruction.
6. **Integration tests on real devices**
    * Set up a Flutter driver or integration test suite to run against physical iOS and Android devices, as well as desktop runners.
7. **Security audit before release**
    * Conduct a thorough review of the code against the `CLAIM_BOUNDARY.md` and `SECURITY.md` models before tagging a 1.0.0 release.
