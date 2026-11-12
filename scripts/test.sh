#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
mkdir -p "$ROOT/dist"
swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -o "$ROOT/dist/session-tests" \
  "$ROOT/Sources/SessionEngine.swift" \
  "$ROOT/Tests/SessionEngineTests.swift" \
  "$ROOT/Tests/main.swift"
"$ROOT/dist/session-tests"
