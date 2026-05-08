#!/usr/bin/env bash
# Local pre-push gate. Runs source guardrails, the Swift unit + parity
# tests, the headless verifiers, and a Release simulator build with
# signing disabled. Mirrored by CI in .github/workflows.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/check-source-guardrails.sh
swift test
swift run FastReadCoreVerifier
swift run FastReadPerformanceVerifier
xcodebuild \
  -project FastRead.xcodeproj \
  -scheme FastRead \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
