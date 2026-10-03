#!/bin/bash
set -e

echo "Verifying pqkeystore package..."

cd "$(dirname "$0")/.."

echo "Running flutter pub get..."
flutter pub get

echo "Running dart analyze..."
dart analyze

echo "Running flutter test..."
flutter test

echo "Verification complete!"
