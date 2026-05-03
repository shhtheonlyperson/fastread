#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/check-source-guardrails.sh
swift test
swift run FastReadCoreVerifier
swift run FastReadPerformanceVerifier
npm test
xcodebuild -project FastRead.xcodeproj -scheme FastRead -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
