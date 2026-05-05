#!/usr/bin/env bash
set -euo pipefail

(
  cd packages/papyrus_platform_interface
  flutter test
  flutter analyze
)

(
  cd packages/papyrus
  flutter test
  flutter analyze
)

for package in \
  packages/papyrus_android \
  packages/papyrus_ios \
  packages/papyrus_macos \
  packages/papyrus_windows \
  packages/papyrus_linux; do
  (
    cd "$package"
    flutter analyze
  )
done

flutter test test/acceptance_test.dart
