# pqkeystore — Linux

Native Linux implementation of
[platform channel contract v1](../doc/PLATFORM_CONTRACT.md) on the
freedesktop **Secret Service** via libsecret. Design and limits:
[ADR-0009](../doc/adr/0009-native-backend-designs.md).

## Storage model

| Property | Value |
| --- | --- |
| Backend | Secret Service (D-Bus), libsecret ≥ 0.18 |
| Schema attributes | `{app, id}` where `app` is the application namespace |
| Secret value | canonical base64 of the PQKS record, `content-type: text/plain` |
| Record size | 1 byte … 1 MiB |
| ID size | 1 … 256 UTF-8 bytes, no U+0000 |
| File fallback | **none, ever** |

Native code stores **one opaque PQKS blob per ID and nothing else**. It never
parses metadata and reserves no ID prefix, so there is no `__meta__` namespace
and no sidecar record.

## No silent fallback — this is a security property

If no Secret Service provider is reachable (headless session, D-Bus session bus
with no activated provider, no default collection), **every** operation fails
with `UNAVAILABLE`. It never quietly writes a file instead.

That behaviour is deliberate and is enforced by a dedicated CI job
(`No silent fallback without a Secret Service`, see
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) which removes the
activatable Secret Service providers from the runner and asserts the failure
mode. If you need to persist records on a machine without a Secret Service,
that is an explicit, opt-in decision by the application
(`BackendType.platformWithFileFallback`), never a silent behaviour of this
plugin.

`SecretStore::Put` maps a missing default collection
(`SECRET_ERROR_NO_SUCH_OBJECT`) to `UNAVAILABLE` for the same reason: a fresh
KWallet or KeePassXC setup with no unlocked collection is not a working secure
store.

## Capabilities

**None.** No optional security option is offered; all of them are rejected with
`UNSUPPORTED_OPTION`:

| Option | Status |
| --- | --- |
| `requireUserPresence` | unsupported |
| `requireBiometric` | unsupported |
| `accessibility.whenUnlocked` | unsupported |
| `accessibility.afterFirstUnlock` | unsupported |
| `synchronizable` | unsupported |

The Secret Service API offers no equivalent of keychain item classes or
access-control flags, so offering them would be a lie. `listIds` is also served
with an `LAContext`-style non-interactive query so that listing never triggers
an unlock prompt.

## Isolation — the honest limitation

The Secret Service provides **no per-application isolation**. Items are scoped
by the `app` attribute only, so *any* process running as the same user in the
same session can search, read or modify these records. At-rest protection is
whatever the provider supplies (gnome-keyring, KWallet ≥ 5.97, KeePassXC) —
that is a property of the provider, not of this plugin.

This is called out in `doc/CLAIM_BOUNDARY.md` rather than left implicit.

## Threading

`pq_keystore_plugin.cc` validates calls on the platform thread and performs
storage work on an exclusive worker thread, returning results on the platform
thread. Argument validation is separated into `pq_keystore_contract.{h,cc}`,
which touches no D-Bus and is therefore unit-testable in isolation.

## Durability

Writes are a single `SecretService` create-or-replace. There is no file, no
rename and no index to corrupt. Partial states are possible only if the
provider itself fails mid-write; a read that finds an item whose stored value
does not strictly decode is reported as `CORRUPT`, never as absent.

## Source map

| File | Role |
| --- | --- |
| `pq_keystore_plugin.cc` | Channel wiring; main-thread validation, exclusive worker thread |
| `pq_keystore_contract.{h,cc}` | Argument validation (no D-Bus, unit-tested) |
| `pq_keystore_secret_store.{h,cc}` | libsecret storage and error mapping |
| `test/pq_keystore_contract_test.cc` | Native unit tests |

## Build

Build dependency: `libsecret-1-dev` (Debian/Ubuntu) or `libsecret-devel`
(Fedora), ≥ 0.18.

## Tests

Native unit tests, from `example/` after `flutter build linux --debug`:

```sh
cmake --build build/linux/x64/debug --target pqkeystore_test
build/linux/x64/debug/plugins/pqkeystore/pqkeystore_test
```

Contract suite against a real Secret Service provider:

```sh
dbus-run-session -- bash -euo pipefail -c '
  echo -n "ci-only" | gnome-keyring-daemon --unlock --components=secrets >/dev/null
  flutter test integration_test/platform_contract_test.dart -d linux
'
```

> Always run this inside a private `dbus-run-session` **and** with a throwaway
> `HOME` (`HOME=$(mktemp -d)`). `gnome-keyring-daemon --unlock` operates on the
> shared on-disk store at `~/.local/share/keyrings/login.keyring` even when the
> session bus is isolated, so running it against your real session keyring will
> re-encrypt your login keyring with the throwaway password and lock you out.

CI runs both the positive and the negative (no provider) case.

## What is NOT claimed

- **Per-application isolation.** See above — any process in the user session
  can read these items.
- **Provider-dependent at-rest protection.** Security is exactly the provider's.
- **Any capability flags.** All are refused with `UNSUPPORTED_OPTION`.
- **Headless/daemon operation.** Without a running Secret Service this plugin
  fails rather than degrading.
