# Publication decision

- Status: **not approved for publication**
- Package version: `0.1.0-dev.1`
- `publish_to`: `none`

This is the publication decision for the current tree. It is not a stable release and it does not close TRK-007, TRK-009, or TRK-012.

- Do not publish. `publish_to: 'none'` is the committed decision. No tag is created by this change.
- A real `dart pub publish` (without `--dry-run`) was not run. The Dart 3.13.7 tool contains the refusal "A private package cannot be published" for that command. `--dry-run` does **not** emit that refusal: on a clean snapshot of this tree it resolves dependencies, prints the archive, reports 0 warnings, and exits 0. It does not upload.
- The clean-snapshot dry-run inspected for this change is recorded with its archive size in the command log below. Tracked names are also rejected by [`test/archive_hygiene_test.dart`](../test/archive_hygiene_test.dart) when they are `.pqks`, a private-key filename, or a PEM-style private-key block. The test prints paths only.
- Do not create a git tag from this change.
- A later tag or pub.dev upload requires a separate maintainer action after TRK-012. This file does not grant that action.
- Native metadata (`darwin/pqkeystore.podspec`, `darwin/pqkeystore/Package.swift`) carries the same version and has no placeholder summary, license, or homepage ([`test/sdk_constraints_test.dart`](../test/sdk_constraints_test.dart)). `pod spec lint` was **not** executed: this host has no CocoaPods and no Xcode, and a green `pod spec lint` is not claimed. What did run is CI [42502723203](https://github.com/turkananation/pqkeystore/actions/runs/42502723203), job "iOS (CocoaPods)", step "Build" (`flutter build ios --simulator` with SwiftPM off). That step succeeded, so CocoaPods installed this podspec and the simulator target compiled. The next step failed on a missing Apple development signing identity, and the contract suite was skipped. That is not a silent pass (TRK-007, TRK-009).

Supported SDK pair and the analyze/test log are in [`SDK_BASELINE.md`](SDK_BASELINE.md).

## Clean-snapshot dry-run

Command, from a temporary git repository containing this working tree (tracked
files plus untracked non-ignored files), Dart 3.13.7 / Flutter 3.47.9, on
2026-11-08:

```sh
dart pub publish --dry-run
```

Exit 0. Compressed archive **430 KB**. `Package has 0 warnings.` The file list
had no `.pqks`, `id_rsa`, `.pem`, `.p12`, or `secret.json` path. Nothing was
uploaded. `--dry-run` did not print the private-package refusal; that refusal
is for a real `dart pub publish`, which was not run.

