#!/usr/bin/env bash
# Automate the spike via the in-app auto-sweep. Capture logcat so the
# parser can extract per-WPM jitter from the FastReadSpike tag.
#
# Usage:
#   ./perf-sweep.sh                       # default sweep
#   RUN_SECONDS=20 ./perf-sweep.sh        # shorter
set -euo pipefail

RUN_SECONDS=${RUN_SECONDS:-25}
SERIAL=${SERIAL:-emulator-5554}
PACKAGE=com.shhtheonlyperson.fastread.spike
ACTIVITY=$PACKAGE/.MainActivity
LOG=/tmp/spike-perf.log
WPM_COUNT=5

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH=$ANDROID_HOME/platform-tools:$PATH

echo "→ stopping any prior instance"
adb -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null

# Clear and start logcat capture in background.
adb -s "$SERIAL" logcat -c
adb -s "$SERIAL" logcat -s FastReadSpike:I > "$LOG" &
LOGCAT_PID=$!
trap 'kill $LOGCAT_PID 2>/dev/null || true' EXIT

adb -s "$SERIAL" shell am start -n "$ACTIVITY" --ei sweep_seconds "$RUN_SECONDS" >/dev/null
echo "→ sweep running ($RUN_SECONDS s × $WPM_COUNT WPMs ≈ $((RUN_SECONDS * WPM_COUNT + 5))s)"

until grep -q "AUTO_SWEEP_DONE" "$LOG" 2>/dev/null; do
  sleep 2
done

echo "→ killing logcat"
kill $LOGCAT_PID 2>/dev/null || true
trap - EXIT
echo "→ log saved to $LOG ($(wc -l < "$LOG") lines)"
python3 "$(dirname "$0")/perf-report.py" "$LOG"
