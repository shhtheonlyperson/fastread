#!/usr/bin/env bash
# Run Maestro flows against a booted iOS simulator with the FastRead
# Debug build installed and the chosen launch arguments seeded.
#
# Usage:
#   scripts/maestro-test.sh                       # run all flows
#   scripts/maestro-test.sh user-dictionary       # run a single flow
#   scripts/maestro-test.sh --report user-dictionary
#                                                 # also record video
#                                                 # + open build/maestro/index.html
#
# Assumes:
#   - macOS with Xcode (xcrun simctl available)
#   - openjdk@21 from Homebrew (Maestro needs Java)
#   - Maestro installed (~/.maestro/bin/maestro)
#
# This builds the Debug FastRead.app for the iPhone simulator if no
# built bundle exists and reuses the booted simulator (boots one if
# none is up). Each flow runs against a fresh install so the
# pre-launch seed args take effect deterministically.
set -euo pipefail

WITH_REPORT=0
if [ "${1:-}" = "--report" ]; then
  WITH_REPORT=1
  shift
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Java for Maestro
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
  fi
fi
export PATH="${JAVA_HOME:-}/bin:$HOME/.maestro/bin:$PATH"

if ! command -v maestro >/dev/null 2>&1; then
  echo "❌ maestro not on PATH. Install with: curl -sSL https://get.maestro.mobile.dev | bash"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "❌ xcrun not found — Xcode required."
  exit 1
fi

# Pin to a specific simulator. Multiple booted sims would otherwise
# race: simctl install/launch resolves "booted" non-deterministically,
# while Maestro independently picks one — so the install can land on a
# different device than the run, and the seed args silently drop.
DEVICE_NAME="${FASTREAD_SIMULATOR_NAME:-iPhone 17 Pro}"
DEVICE_UDID="$(
  xcrun simctl list devices available -j 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devs in data['devices'].items():
    for d in devs:
        if d['name'] == '$DEVICE_NAME' and d.get('isAvailable', False):
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" || true
)"
if [ -z "$DEVICE_UDID" ]; then
  echo "❌ no simulator named '$DEVICE_NAME'. Override with FASTREAD_SIMULATOR_NAME=…"
  exit 1
fi

DEVICE_STATE="$(xcrun simctl list devices -j 2>/dev/null \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devs in data['devices'].items():
    for d in devs:
        if d['udid'] == '$DEVICE_UDID':
            print(d.get('state', 'Unknown'))
            sys.exit(0)
" || true)"

if [ "$DEVICE_STATE" != "Booted" ]; then
  echo "→ booting $DEVICE_NAME ($DEVICE_UDID)…"
  xcrun simctl boot "$DEVICE_UDID" 2>/dev/null || true
  open -a Simulator
  sleep 8
fi

echo "→ using simulator $DEVICE_NAME ($DEVICE_UDID)"

# Build the simulator .app if we don't already have one we can install.
DERIVED="${FASTREAD_DERIVED:-/tmp/fastread-derived}"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/JustRead.app"
if [ ! -d "$APP_PATH" ]; then
  echo "→ building Debug FastRead.app for iOS simulator…"
  xcodebuild \
    -project FastRead.xcodeproj \
    -scheme FastRead \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" \
    -configuration Debug \
    build >/dev/null
fi

BUNDLE_ID="com.shhtheonlyperson.fastread"

# (Re)install on the pinned device. Uninstall first so the seeded
# launch args produce a deterministic library state.
xcrun simctl uninstall "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_UDID" "$APP_PATH"

# Per-flow launch args. Add new entries here when adding new flows
# rather than smuggling logic into the YAML.
flow_launch_args() {
  case "$1" in
    user-dictionary)
      printf '%s\0' \
        "-FASTREAD_RESET_LIBRARY" \
        "-FASTREAD_SEED_DRAFT_TEXT" "黃士旗去吃飯與星巴克碰面。" \
        "-FASTREAD_SEED_DRAFT_TITLE" "User dict smoke"
      ;;
    *)
      printf '%s\0' "-FASTREAD_RESET_LIBRARY"
      ;;
  esac
}

prelaunch_with_args() {
  local flow_name="$1"
  # Terminate any prior instance so the next launch sees the fresh args.
  xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
  # Read NUL-separated args into a bash array safely.
  local args=()
  while IFS= read -r -d '' arg; do
    args+=("$arg")
  done < <(flow_launch_args "$flow_name")
  xcrun simctl launch "$DEVICE_UDID" "$BUNDLE_ID" "${args[@]}" >/dev/null
}

# Pick which flow(s) to run.
FLOW_FILTER="${1:-}"
FLOWS=(.maestro/*.yaml)
if [ -n "$FLOW_FILTER" ]; then
  FLOWS=(.maestro/*"$FLOW_FILTER"*.yaml)
fi

EXIT=0
for flow in "${FLOWS[@]}"; do
  if [ ! -f "$flow" ]; then
    echo "no flow matched: $FLOW_FILTER"
    exit 2
  fi
  flow_name="$(basename "${flow%.yaml}")"
  echo "▶ $flow"
  prelaunch_with_args "$flow_name"
  mkdir -p build/maestro
  if ! maestro --device "$DEVICE_UDID" test \
      --format HTML-DETAILED \
      --output "build/maestro/${flow_name}.html" \
      --debug-output "build/maestro/debug" \
      "$flow"; then
    EXIT=1
  fi
  if [ "$WITH_REPORT" -eq 1 ] && [ "$EXIT" -eq 0 ]; then
    echo "  → recording video for $flow_name…"
    prelaunch_with_args "$flow_name"
    maestro --device "$DEVICE_UDID" record --local \
      "$flow" "build/maestro/${flow_name}.mp4" >/dev/null
    echo "  → stitching index.html…"
    python3 "$ROOT/scripts/maestro-report.py"
    open "build/maestro/index.html" 2>/dev/null || true
  fi
done

exit $EXIT
