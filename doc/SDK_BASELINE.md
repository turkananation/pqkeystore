# SDK baseline (TRK-001)

Approved minimum: **Dart 3.12.2 / Flutter 3.44.2**.

That is the oldest stable Flutter that ships a Dart SDK able to resolve this
package. `pqthreshold` 1.1.0 requires Dart `^3.12.2`. Flutter 3.44.0 is Dart
3.12.0 and `flutter pub get` fails there. Flutter 3.24.0 is Dart 3.5.0 and is
not a supported floor. The manifests say `sdk: '>=3.12.2 <4.0.0'` and
`flutter: '>=3.44.2'` in both the package and the example.

Current local toolchain for the second run: **Dart 3.13.7 / Flutter 3.47.9**.
CI's other jobs stay on Flutter **3.47.5** (Dart 3.13.4). A `dart-minimum` job
runs `tool/verify.sh` on Flutter 3.44.2. CI run 42502723203 passed the Dart
job on 3.47.5 before the tests added in this change; it is not the count below.

This file does not claim a production audit. Commands were run as a non-root
user namespace (`unshare --user --map-user=1000`) so the file-backend
permission test is meaningful. Logs contained no key material.

## What was run

Both toolchains:

- `flutter pub get` in the package and in `example/` succeeded.
- `dart analyze` on the package and on `example/` reported no issues.
- `flutter test` in `example/` passed: **1** test.

`flutter pub get` on Flutter 3.44.2 rewrites six transitive packages downward
(`clock`, `matcher`, `meta`, `stack_trace`, `test_api`, `vector_math`). Those
rewrites are not committed. The lockfile keeps the Flutter 3.47 resolution.
Only the Flutter SDK lower bound in the lock changes, from `>=3.24.0` to
`>=3.44.2`.

## Package test count: 167

A single `flutter test` process on this host does not stay up. `flutter_tester`
drops some files with `WebSocketException: Invalid WebSocket upgrade request`
before any assertion runs. That is a loader failure. It is not a skipped test
and not a passing test. Each dropped file was run again by itself.

No assertion failure was observed.

| Toolchain | One `flutter test` process | Files that failed to load, then passed alone | Sum |
| --- | --- | --- | --- |
| Dart 3.12.2 / Flutter 3.44.2 | `+146 -4` | `doc_links` 1, `kdf_bounds` 7, `sealed_record` 6, `share_custody` 7 | **167** |
| Dart 3.13.7 / Flutter 3.47.9 | `+153 -3` | `secret_lifetime` 6, `doc_links` 1, `kdf_bounds` 7 | **167** |

The two dropped sets are different and both sums are 167, which is the package
test count recorded for this tree. There is no single process summary line of
`+167: All tests passed` from this host. CI's `flutter test` is the place that
can still produce one.
