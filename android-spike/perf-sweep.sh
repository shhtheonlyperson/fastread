#!/usr/bin/env bash
# Automate the spike: tap each WPM pill, tap START, let it run
# RUN_SECONDS, tap STOP, repeat. Capture logcat throughout so the
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
WPMS=(600 800 1000 1200)

# Coordinates derived from the 1080x2400 PERF SPIKE screenshot.
pace_x_for() {
  case "$1" in
    600) echo 265 ;;
    800) echo 415 ;;
    1000) echo 580 ;;
    1200) echo 740 ;;
    *) echo 540 ;;
  esac
}
PACE_Y=1410
START_X=540
START_Y=1620

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH=$ANDROID_HOME/platform-tools:$PATH

echo "→ stopping any prior instance"
adb -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null
adb -s "$SERIAL" shell am start -n "$ACTIVITY" >/dev/null
sleep 2

# Clear and start logcat capture in background.
adb -s "$SERIAL" logcat -c
adb -s "$SERIAL" logcat -s FastReadSpike:I > "$LOG" &
LOGCAT_PID=$!
trap 'kill $LOGCAT_PID 2>/dev/null || true' EXIT

for wpm in "${WPMS[@]}"; do
  echo "▶ wpm=$wpm  (${RUN_SECONDS}s sample)"
  adb -s "$SERIAL" shell input tap "$(pace_x_for "$wpm")" "$PACE_Y"
  sleep 0.3
  adb -s "$SERIAL" shell input tap "$START_X" "$START_Y"
  sleep "$RUN_SECONDS"
  adb -s "$SERIAL" shell input tap "$START_X" "$START_Y"  # toggles to STOP
  sleep 0.5
done

echo "→ killing logcat"
kill $LOGCAT_PID 2>/dev/null || true
trap - EXIT
echo "→ log saved to $LOG ($(wc -l < "$LOG") lines)"
