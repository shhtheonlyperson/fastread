#!/usr/bin/env bash
# Local Android verifier for the native android-spike project.
#
# Runs JVM unit tests through the checked-in Gradle wrapper. The current
# parity corpus test is ignored on desktop JVM because Android's ICU-backed
# BreakIterator differs from java.text.BreakIterator; move that test to
# androidTest before treating Android tokenizer parity as fully gated.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
fi
if [ -n "${JAVA_HOME:-}" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

if ! command -v java >/dev/null 2>&1; then
  echo "[verify-android] java not on PATH. Install OpenJDK 21 or set JAVA_HOME." >&2
  exit 1
fi

cd "$ROOT_DIR/android-spike"
./gradlew :app:testDebugUnitTest
