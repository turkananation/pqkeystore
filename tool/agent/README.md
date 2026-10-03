# Agent Tooling

This directory contains scripts and tools specifically intended for automated verification and agent-driven development workflows.

## `verify.sh`

A standard bash script to validate the integrity of the package. It runs:
1.  `flutter pub get`
2.  `dart analyze`
3.  `flutter test`

Agents should run this script frequently (e.g., via `tool/verify.sh`) to ensure their changes have not broken the build, introduced static analysis errors, or failed any unit tests. The script exits with a non-zero code on the first failure.
