#!/bin/bash
# Pure-Dart verification gate (no device, no native toolchain required).
# Native builds and the on-device contract suite run in .github/workflows/ci.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Verifying pqkeystore package..."

if [ -n "$(git ls-files '*.pqks' 2>/dev/null)" ]; then
  echo "ERROR: *.pqks files are committed (AGENTS rule 9)." >&2
  exit 1
fi

echo "Running flutter pub get..."
flutter pub get

echo "Running dart analyze..."
dart analyze

echo "Running flutter test (unit + reference contract suite)..."
flutter test

echo "Verifying example..."
(
  cd example
  flutter pub get
  dart analyze
  flutter test
)

echo "Verification complete!"
