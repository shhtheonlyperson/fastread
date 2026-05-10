#!/usr/bin/env bash
# Build, install, and run the auto-sweep on a connected real device.
# No tap automation needed — the spike app picks up `sweep_seconds`
# from the launch intent and cycles 600 / 800 / 1000 / 1200 wpm in-app.
#
# Usage:
#   ./real-device-sweep.sh                 # auto-pick the first non-emulator
#   SERIAL=ABCD1234 ./real-device-sweep.sh # pin to a specific device
#   SECONDS_PER_WPM=30 ./real-device-sweep.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/.."

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH=$ANDROID_HOME/platform-tools:$PATH
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}

SECONDS_PER_WPM=${SECONDS_PER_WPM:-25}
PACKAGE=com.shhtheonlyperson.fastread.spike
ACTIVITY=$PACKAGE/.MainActivity
LOG=/tmp/spike-perf-real.log

# Pick a device. Prefer non-emulator unless SERIAL is set.
if [ -z "${SERIAL:-}" ]; then
  SERIAL=$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')
  if [ -z "$SERIAL" ]; then
    echo "❌ no real device attached. Connect via USB, enable USB debugging, then re-run."
    echo "   Currently visible:"
    adb devices
    exit 1
  fi
fi

echo "→ device: $SERIAL"
adb -s "$SERIAL" shell getprop ro.product.model
adb -s "$SERIAL" shell getprop ro.build.version.release
echo

# Build + install.
echo "→ assembleDebug"
gradle -q :app:assembleDebug -p "$ROOT" >/dev/null
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
adb -s "$SERIAL" install -r "$APK" | tail -1

# Run sweep.
adb -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null
adb -s "$SERIAL" logcat -c
adb -s "$SERIAL" shell am start -n "$ACTIVITY" --ei sweep_seconds "$SECONDS_PER_WPM" >/dev/null
echo "→ sweep running ($SECONDS_PER_WPM s × 4 WPMs ≈ $((SECONDS_PER_WPM * 4 + 5))s)"

# Wait for the marker the app emits when all four WPMs are done.
until adb -s "$SERIAL" logcat -d -s FastReadSpike:I 2>/dev/null | grep -q "AUTO_SWEEP_DONE"; do
  sleep 2
done

adb -s "$SERIAL" logcat -d -s FastReadSpike:I > "$LOG"
echo "→ log saved to $LOG ($(wc -l < "$LOG") lines)"
echo

python3 "$ROOT/perf-report.py" "$LOG"
