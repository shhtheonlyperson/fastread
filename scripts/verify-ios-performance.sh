#!/usr/bin/env bash
# Local pre-push gate. Runs source guardrails, the Swift unit + parity
# tests, the headless verifiers, a Release simulator build with signing
# disabled, and the FastReadUITests happy-path XCUITest. Mirrored by CI
# in .github/workflows.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Pinned simulator: iPhone 17 Pro on iOS 26.4. Override via
# FASTREAD_UI_TEST_DESTINATION_ID to retarget on machines that have a
# different simulator UDID.
UI_TEST_DESTINATION_ID="${FASTREAD_UI_TEST_DESTINATION_ID:-0CC71FC3-7C33-4707-A627-554BCB569549}"

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

# UI test: skips automatically when the EPUB fixture is unavailable.
if [ ! -f "$ROOT_DIR/test.epub" ] && [ -z "${FASTREAD_E2E_EPUB:-}" ]; then
  echo "[verify] Skipping FastReadUITests — no test.epub at repo root and FASTREAD_E2E_EPUB not set."
else
  xcodebuild \
    -project FastRead.xcodeproj \
    -scheme FastReadUITests \
    -destination "platform=iOS Simulator,id=${UI_TEST_DESTINATION_ID}" \
    CODE_SIGNING_ALLOWED=NO \
    test
fi
