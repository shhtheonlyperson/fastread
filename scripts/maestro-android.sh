#!/usr/bin/env bash
# Build, install, and run the Android Maestro flow on a booted
# emulator (or connected device). Mirrors scripts/maestro-test.sh
# but for the JustRead Android app.
#
# Usage:
#   scripts/maestro-android.sh                       # all flows
#   scripts/maestro-android.sh user-dictionary       # one flow
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:$HOME/.maestro/bin:$PATH"

if ! command -v maestro >/dev/null 2>&1; then
  echo "❌ maestro not on PATH. Install with: curl -sSL https://get.maestro.mobile.dev | bash"
  exit 1
fi

# Prefer a real device; fall back to emulator if none.
DEVICE_UDID=$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')
if [ -z "$DEVICE_UDID" ]; then
  DEVICE_UDID=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
fi
if [ -z "$DEVICE_UDID" ]; then
  echo "❌ no Android device or emulator booted. Boot Pixel_8_API_35:"
  echo "   emulator @Pixel_8_API_35 -no-window -no-audio -no-snapshot-load &"
  exit 1
fi
echo "→ device: $DEVICE_UDID"

# Build + install debug APK.
"$ROOT/android-spike/gradlew" -q :app:assembleDebug -p "$ROOT/android-spike" >/dev/null
APK="$ROOT/android-spike/app/build/outputs/apk/debug/app-debug.apk"
adb -s "$DEVICE_UDID" install -r "$APK" >/dev/null
echo "→ installed $APK"

FLOW_FILTER="${1:-android-user-dictionary}"
FLOWS=(.maestro/android-*"$FLOW_FILTER"*.yaml)
[ "${1:-}" = "" ] && FLOWS=(.maestro/android-*.yaml)

EXIT=0
mkdir -p build/maestro-android
for flow in "${FLOWS[@]}"; do
  [ -f "$flow" ] || { echo "no flow matched: $FLOW_FILTER"; exit 2; }
  flow_name="$(basename "${flow%.yaml}")"
  echo "▶ $flow"
  if ! maestro --device "$DEVICE_UDID" test \
      --format HTML-DETAILED \
      --output "build/maestro-android/${flow_name}.html" \
      --debug-output "build/maestro-android/debug" \
      "$flow"; then
    EXIT=1
  fi
done
exit $EXIT
