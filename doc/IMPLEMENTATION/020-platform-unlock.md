# 0.2.0 — Platform unlock

Per-write storage options, a real `PlatformUnlock`, a real
`PassphraseThenPlatform` chain, capability negotiation as a public API, and
Android user presence.

This is also the release that removes `StubKeystoreCrypto` and lands Part B
(additive half) and Part C of
[`CROSS-CUTTING.md`](CROSS-CUTTING.md). Those three are prerequisites for this
work, not optional companions.

---

## 1. Current state

### 1.1 Options are backend-scoped, not per-write

`PlatformKeystoreBackend` holds a single `PlatformStoreOptions` for its whole
lifetime:

- `lib/src/backend/platform_keystore_backend.dart:37` — default
  `const PlatformStoreOptions()`
- `:44` — `final PlatformStoreOptions options;`
- `:100` — `options.validateCombination()`
- `:102` — capability check against `PlatformInfo.supportedOptions`
- `:115` — `PlatformContract.argOptions: options.toChannelMap()`

Consequences:

- One keystore instance means one protection level for every record it holds.
  To store one record requiring user presence next to one that does not, an app
  needs two `PqKeystore` instances over two backends.
- `use`/`delete` send no options at all, which is correct today and must stay
  correct: **options are a write-time enforcement request only.** Reading a
  record must never be gated on options the reader did not supply.
- `PqKeystore.put` has no parameter through which a caller could even express
  this; it does not know a `PlatformStoreOptions` exists.

### 1.2 `PlatformUnlock` is rejected before the backend is reached

- `lib/src/api/pq_keystore.dart:55-57` — `if (unlock is PlatformUnlock) return
  const KsFailure(PolicyError('v1 requires PassphraseUnlock or
  PassphraseThenPlatform'))`
- `lib/src/crypto/pq_forge_keystore_crypto.dart:135` — the same rejection again,
  as `CryptoError`, in `_passphraseBytes`.

The second one matters: it means the policy is currently enforced by the *crypto
adapter*, not by the facade. Any other adapter would silently accept
`PlatformUnlock` and treat it as no protection at all. That is the defect this
version removes.

### 1.3 `PassphraseThenPlatform` is a lie

`_passphraseBytes` pattern-matches `PassphraseThenPlatform(:final passphrase)`
and returns the passphrase. The platform step is never requested, never
performed, and never reported. An app asking for passphrase **then** device
authentication gets passphrase only, and `use()` succeeds — the OS prompt never
appears.

### 1.4 Native side

- Android: PQNA v2 wraps the record key with an AndroidKeyStore AES-256-GCM key.
  `setUserAuthenticationRequired` / `setUserPresenceRequired` are not set
  today, and the alias cannot be marked invalid-on-enrollment-change.
- Apple: data-protection keychain, `base64url(UTF-8 ID)` accounts. `SecAccessControl`
  is not used; accessibility is the only control.
- Windows: DPAPI files (PQNW), user scope. No user-presence concept in DPAPI
  without a credential-provider design — genuinely unsupported.
- Linux: Secret Service. `org.freedesktop.Secret.Service` prompts are
  collection-owned and outside this plugin's control — unsupported.

### 1.5 Capability negotiation is internal-only

`PlatformContract.capabilities` is a closed set of five names, and the backend
subtracts `options.requiredCapabilities` from `PlatformInfo.supportedOptions`
internally (`platform_keystore_backend.dart:102`). There is no way for an
application to ask "can this device do this?" *before* attempting a write.

---

## 2. Target state

### 2.1 `put` takes options

```dart
Future<KsResult<void>> put(
  KeyMetadata metadata,
  Uint8List plaintext,
  UnlockMethod unlock, {
  PlatformStoreOptions? storeOptions,
})
```

`storeOptions` is **meaningful only** when the backend is a
`PlatformKeystoreBackend`, and for every other backend the rule is:

- `null` → unchanged behaviour, no behaviour change for any existing caller.
- non-null → `KsFailure(PolicyError('storeOptions is only supported by
  PlatformKeystoreBackend'))`.

Silently ignoring it on a memory or file backend would violate the same
"refuse, never ignore" principle the natives already follow. The facade must
know its backend type, so `PqKeystore` gains a private `bool get _isPlatform =>
_backend is PlatformKeystoreBackend`.

`putShare` gains the same named parameter with the same rule.

### 2.2 `PlatformStoreOptions` becomes a per-write value

`PlatformKeystoreBackend.options` becomes a **default** rather than a mandate:

```dart
PlatformKeystoreBackend({PlatformStoreOptions? options})
    : options = options ?? const PlatformStoreOptions();
```

Resolution order in `putSealed`, with no fourth source:

1. `writeOptions` (the per-call argument), if non-null;
2. otherwise `this.options`;
3. otherwise `const PlatformStoreOptions()`.

Step 2 is what preserves every existing caller. A caller who constructed a
backend with options gets the same behaviour as before, forever.

### 2.3 `PlatformUnlock` really unlocks

The facade stops rejecting `PlatformUnlock`. Instead, dispatch moves into a
three-method crypto interface so each adapter declares what it can do.

`lib/src/crypto/keystore_crypto.dart`:

```dart
/// Which custody mechanism protects a record.
///
/// Returned by [PqKeystoreCrypto.supportsUnlock] so the facade can refuse an
/// unlock method no adapter will honour, instead of letting an adapter
/// reinterpret it as something weaker.
enum CryptoProvider { pqforge, platform }
```

`PqKeystoreCrypto` gains:

```dart
/// The provider backing this adapter.
CryptoProvider get provider;

/// The unlock methods this adapter will honour for [options].
///
/// Implementations must answer from their own capability set, never from the
/// caller's intent. Returning `true` for a method the adapter silently degrades
/// is a contract violation.
Set<UnlockKind> supportedUnlocks(PlatformStoreOptions options);

/// Whether this adapter performs a device-authentication step.
bool get requiresDeviceAuthentication;
```

and `UnlockMethod` gains a `UnlockKind get kind` on each of its three members
(`passphrase`, `platform`, `passphraseThenPlatform`) so the comparison is
exhaustive and pattern-matchable rather than `is`-checked in three places.

**Dispatch rules in `PqKeystore.put` / `use` / `putShare` / `useShare`:**

| `UnlockMethod` | `CryptoProvider.pqforge` | `CryptoProvider.platform` |
| --- | --- | --- |
| `PassphraseUnlock` | wrap/unwrap as today | unwrap via native OS unlock, then wrap under a store-local random key |
| `PlatformUnlock` | `PolicyError('pqforge cannot honour PlatformUnlock')` | native OS unlock only |
| `PassphraseThenPlatform` | `PolicyError('this record is not device-gated; use PassphraseUnlock')` | native OS unlock **then** passphrase-derived inner key |

Two subtleties that must be right:

- `PassphraseThenPlatform` against the `pqforge` adapter must **fail**, not
  silently degrade. Today it degrades. A caller who asked for two factors got
  one, and `use()` reported success. Failing closed is the whole point.
- `PassphraseThenPlatform` against the `platform` adapter is genuinely two
  layers: the OS releases the outer key (user presence/biometric or device
  unlock), *and* a passphrase-derived inner key is required. Both must be
  present. Order is OS-first, then passphrase — the user is prompted once, by
  the OS, and the passphrase derivation happens after, inside the native
  platform.

### 2.4 New adapter: `PlatformKeystoreCrypto`

New file `lib/src/crypto/platform_keystore_crypto.dart`. It wraps/unwraps
through a `PqKeystoreBackend`'s native unlock, never through a Dart KDF:

- `wrap(plaintext, aad, unlock, storeOptions)`: generate a 32-byte store-local
  key from `Random.secure()`, hand it to the native side with the record's
  metadata and options, wipe the Dart copy immediately. **The store-local key is
  the only secret, and it exists only in the native store.**
- `unwrap(ciphertext, aad, nonce, wrapAlg, unlock, kdfParams)`: the native side
  decrypts and returns plaintext; Dart wipes its copy per rule 10.

`wrapAlgId = 'platform-os-unlock/v1'`. `unwrap` refuses any other `wrapAlg`
with `CryptoError` — the same guard `PqForgeKeystoreCrypto` already has, and for
the same reason.

Native work needed per platform:

- **Android** — PQNA v2 gains `requireUserPresence` and `requireBiometric` in
  its envelope header, and sets
  `KeyGenParameterSpec.setUserAuthenticationRequired(true)` plus
  `setUserPresenceRequired(true)` (or
  `setInvalidatedByBiometricEnrollment(true)` for the biometric case) on the
  wrapping alias. `setInvalidatedByBiometricEnrollment` is the strong option:
  enrollment changes destroy the key. The Android leg needs a
  `BiometricPrompt` hosted by a `FragmentActivity` — see §2.5.
- **Apple** — `SecAccessControlCreateWithFlags` with
  `.biometryCurrentSet` or `.userPresence` combined with the chosen
  `kSecAttrAccessible*`. `.biometryCurrentSet` deliberately matches
  `requireBiometric`'s "invalidated if enrollment changes" doc comment; Apple
  offers no way to request a weaker "any biometric" control through
  `SecAccessControl`, so `requireBiometric` means *current-set*.
  `kSecAttrSynchronizable` stays mutually exclusive, as
  `validateCombination()` already enforces.
- **Windows** — no change. `requireUserPresence`, `requireBiometric` and
  `synchronizable` are not in `platformInfo.supportedOptions` for Windows, so
  the existing capability check returns `UNSUPPORTED_OPTION` and that is the
  correct, documented answer.
- **Linux** — no change, same reasoning.

### 2.5 Android user presence

`BiometricPrompt` requires a `FragmentActivity`, and a plugin has no activity by
default. Introduce an activity-scoped flow, in this order:

1. `PqKeystorePlugin` implements `ActivityAware`. It keeps a nullable `Activity`
   reference and only ever uses it for the prompt lifetime.
2. On a `put`/`unwrap` that requires user presence, if the activity is null or
   not a `FragmentActivity`, return `PlatformError(UNAVAILABLE)` naming the
   missing host. Do not attempt and do not fall back.
3. The prompt is launched with
   `BiometricPrompt(activity, executor, callback)`, using
   `PromptInfo` with a negative button and `setConfirmationRequired(false)`.
4. **Device-credential fallback**: when `requireBiometric` is false,
   `PromptInfo.setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL)`
   and `setNegativeButtonText` must **not** be set — the framework rejects that
   combination. Handle `ERROR_NO_BIOMETRICS` by retrying once with
   `DEVICE_CREDENTIAL` only. This is the single most common
   `IllegalArgumentException` in this flow and it must be handled, not assumed
   away.
5. Cancellation → `USER_CANCELLED`; three failures → `AUTH_FAILED`. Both map to
   existing `PlatformErrorCode` values; no new codes are introduced.
6. The prompt's completion is bridged to the channel's `Result` exactly once.
   A native callback firing twice (prompt dismissed *and* activity destroyed) is
   the classic double-callback bug here: guard with an `AtomicBoolean` per
   invocation.

`dartdoc` on `PlatformStoreOptions.requireUserPresence` must state that it needs
an activity host, and the README's Android section must show the
`FragmentActivity` requirement. A capability that silently fails when the host is
wrong is worse than one that is documented as needing a host.

### 2.6 Capability negotiation is public

```dart
/// What this device can enforce for a given set of storage options.
final class PlatformCapabilities {
  const PlatformCapabilities({
    required this.os,
    required this.supportedOptions,
    required this.contractVersion,
  });

  final String os;
  final Set<String> supportedOptions;
  final int contractVersion;

  /// Whether every option in [options] can be enforced here.
  ///
  /// Pure, offline, and no key material is involved — safe to call at startup.
  bool canEnforce(PlatformStoreOptions options) =>
      options.requiredCapabilities.every(supportedOptions.contains);
}

/// Query the current device.
///
/// Returns [PlatformCapabilities] for the resolved platform. On a non-platform
/// backend, or where the plugin is unregistered, returns a `PlatformCapabilities`
/// with `os: 'unsupported'` and an empty set — every `canEnforce` query is then
/// `false`, which is the safe direction.
Future<KsResult<PlatformCapabilities>> capabilities();
```

Add it as a method on `PqKeystore`. It is a *query*, not an operation: it must
work before any backend write, must not require a `KeyMetadata`, and must not
trigger an unlock prompt.

---

## 3. Change list

Ordered; no task depends on a later one.

- **P-1** `lib/src/api/unlock.dart`: add `UnlockKind` enum (`passphrase`,
  `platform`, `passphraseThenPlatform`) and a `kind` getter on each of the three
  existing members. No existing member changes shape — `sealed` stays sealed.
- **P-2** `lib/src/crypto/keystore_crypto.dart`: add `CryptoProvider`,
  `provider`, `supportedUnlocks`, `requiresDeviceAuthentication` to
  `PqKeystoreCrypto`. Stub references removed here per
  [`CROSS-CUTTING.md`](CROSS-CUTTING.md) Part A.
- **P-3** `PqForgeKeystoreCrypto`: implement the four members.
  `supportsUnlock`/`supportedUnlocks` returns `{UnlockKind.passphrase}`.
  `requiresDeviceAuthentication` is `false`. Its `wrap` gains an optional
  `storeOptions` parameter it **ignores**, documented as: *the pqforge provider
  enforces no device policy; `storeOptions` is only honoured by
  `CryptoProvider.platform`. The facade refuses the combination before this is
  reached.* This keeps one interface for both providers.
- **P-4** `PqKeystore`: add `_isPlatform`, the `storeOptions` named parameter on
  `put`/`putShare`, and the dispatch table from §2.3. Implement
  `capabilities()`.
- **P-5** `PlatformKeystoreBackend`: `options` becomes a default; `putSealed`
  takes an optional per-write override and resolves per §2.2. Extract the
  capability check into a small `validateOptions(PlatformStoreOptions)` method so
  both `put` and `platformInfo` paths share it.
- **P-6** `lib/src/crypto/platform_keystore_crypto.dart`: new adapter. Needs a
  seam for the native call — an interface, not a concrete backend, so it is unit
  testable without a device.
- **P-7** Natives: Android PQNA v2 header + `KeyGenParameterSpec` flags +
  `ActivityAware` + `BiometricPrompt`; Apple `SecAccessControl`; Windows and
  Linux unchanged. Update [`../FORMATS.md`](../FORMATS.md) for the PQNA v2 header
  and the keychain item layout **before** the native code lands — a byte-format
  change with a stale spec is how platforms drift apart.
- **P-8** Contract suite: new cases for per-write options, `PlatformUnlock`,
  `PassphraseThenPlatform` both directions, `KEY_INVALIDATED`, and cancellation.
- **P-9** `BackendFactory`: construct `PlatformKeystoreCrypto` for platform
  backends by default, with an explicit override parameter. Existing code that
  passes an explicit `PqForgeKeystoreCrypto` keeps working unchanged.

## 4. Test plan

### 4.1 Pure Dart (no device)

| Test | File | Assertion |
| --- | --- | --- |
| `storeOptions` on a memory backend | `test/platform_options_scope_test.dart` | `put(…, storeOptions: …)` → `KsFailure(PolicyError)`, and `MemoryKeystoreBackend.putCount` unchanged. Proves "refuse, never ignore". |
| Provider dispatch table | `test/unlock_dispatch_test.dart` | All 3 × 2 cells of §2.3, including the `PassphraseThenPlatform`+pqforge → `PolicyError` cell that today silently succeeds. This test must fail on `main`. |
| Backend default preserved | same | `PlatformKeystoreBackend(options: X)` + `put` with no override still sends `X`; with an override, the override wins. Assert on the captured channel argument map. |
| Capability query | `test/capabilities_test.dart` | On the fake channel: `canEnforce` true only when every `requiredCapabilities` entry is reported; empty set ⇒ every query false. `capabilities()` never invokes `put`/`get`/`delete`. |
| `UnlockKind` exhaustiveness | `test/unlock_kind_test.dart` | `switch` over `UnlockKind` with no `default` compiles; all three `UnlockMethod` members map correctly. |
| Unsupported on Windows/Linux | `test/platform_options_scope_test.dart` | With a `platformInfo` reporting no biometric capability, `put(…, storeOptions: requireBiometric)` → `KsFailure(PlatformError(UNSUPPORTED_OPTION))` and the native side is never called. |

### 4.2 Contract suite (all five targets)

New cases in `test/contract/platform_contract_suite.dart`:

- `put` with `requireUserPresence: false, accessibility: whenUnlocked` → success;
  `get` succeeds.
- `put` with a capability the target does not report → `UNSUPPORTED_OPTION`,
  and **no partial record left behind** (assert `contains(id) == false` after).
- `put` with `synchronizable: true` combined with `requireBiometric: true` →
  `UNSUPPORTED_OPTION` on every target, including ones lacking both features.
  This is the one case that is deterministic everywhere.
- `get` while the OS reports locked → `LOCKED`.
- Prompt cancelled → `USER_CANCELLED`; three failures → `AUTH_FAILED`.
- Biometric enrollment changed → `KEY_INVALIDATED`, and the record stays
  permanently unreadable — the test asserts a second `get` also fails rather than
  succeeding after re-enrollment. Android and Apple only; skipped elsewhere.

### 4.3 Manual / hardware

Not automatable in this repo's CI, and must be recorded as *not run* rather than
assumed: real `BiometricPrompt` on a device with enrolled biometrics; real
`SecAccessControl` with Touch ID/Face ID; device-locked `get` on a physical
device. Add a table to the 0.2.0 release notes with each row marked pass or
not-run. Never claim a hardware path was exercised from a unit test.

## 5. Exit gate

Copied from [`../ROADMAP.md`](../ROADMAP.md) § *0.2.0*: the shared conformance
suite passes on all five targets with the new options, and the Apple legs are
unblocked by a provisioned signing identity.

Additional, specific to this document:

- `PassphraseThenPlatform` either performs both steps or refuses. It may not
  degrade. A regression test pins this.
- `unsupportedOption` is never downgraded to a warning anywhere in the stack.
- `doc/FORMATS.md` describes every byte the natives read and write, updated
  before the natives changed.

## 6. Non-goals

- **No biometrics on Windows or Linux.** DPAPI and Secret Service have no
  equivalent in this design. Returning `UNSUPPORTED_OPTION` is the feature.
- **No TPM or Windows Hello binding.** Out of scope for 0.2.0.
- **No silent degradation of `UNSUPPORTED_OPTION` into a default.** If a device
  cannot enforce what was asked, the write does not happen.
- **No new `PlatformErrorCode` values.** Everything needed exists. A new code
  means the analysis above missed a case — come back and add it here first.
- **No claim that user presence protects against a compromised OS.** It raises
  the bar for casual access; it is not a boundary against root on the device.
  That belongs in [`../CLAIM_BOUNDARY.md`](../CLAIM_BOUNDARY.md) as a non-claim,
  and it must be written *before* 0.2.0 ships, not after.